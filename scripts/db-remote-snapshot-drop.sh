#!/usr/bin/env bash
# db-remote-snapshot-drop.sh (alias: rdbsndrop)
#
# Delete .bak snapshot file(s) from a configured remote SQL Server target's
# backup path (the stored backups, NOT the live databases). Mirrors
# db-remote-backup.sh (rdbsn) / db-remote-restore.sh (rdbr) for server
# selection, then:
#   1. lists .bak snapshots in the server's backup path (with size shown),
#   2. lets you multi-select which ones to delete (TAB to mark),
#   3. mounts the SMB share and shows the local file next to each SQL path,
#   4. requires typing 'delete' to confirm,
#   5. removes the regular file when its size still matches the SQL listing,
#   6. reports how much space was freed.
#
# Safety: nothing is deleted until you type 'delete'. A symlink, a missing
# file, or a size mismatch aborts before that prompt. Only files whose
# post-delete existence check confirms removal count toward "space freed".
# macOS and Linux only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/scripts/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/scripts/forge.sh"
fi

die() { echo "✖ $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) die "rdbsndrop runs on macOS and Linux. This station reported $(uname -s)." ;;
esac
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

require_cmd fzf
require_cmd jq
require_cmd python3
require_cmd sqlcmd
require_cmd stat

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/backup-share-path.sh"

FORGE_ROOT="${FORGE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RUNTIME_CONFIG_FILE="${FORGE_ROOT}/linux/config/runtime.json"
[[ -f "$RUNTIME_CONFIG_FILE" ]] || die "Missing runtime config: $RUNTIME_CONFIG_FILE"

SQLCMD_BIN="${FORGE_SQLCMD_BIN:-$(command -v sqlcmd)}"
SQLCMD_GODEBUG="${FORGE_SQLCMD_GODEBUG:-x509negativeserial=1}"

LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$HOME/mac-forge/config-local}/local-store.json"
[[ -f "$LOCAL_STORE_FILE" ]] || die "Missing local store file: $LOCAL_STORE_FILE"

#######################################
# Small helpers
#######################################
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

escape_tsql_string() {
  local s="$1"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

expand_home() {
  local path="$1"

  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#"~/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

is_mounted() {
  local target="$1"

  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$target"
    return
  fi
  mount | grep -F " on ${target} (" >/dev/null 2>&1
}

ensure_linux_mount() {
  local source="$1" target="$2" credentials="$3" extra_options="$4"
  local options

  is_mounted "$target" && return 0

  require_cmd mount.cifs
  require_cmd sudo
  require_cmd timeout

  echo "Share not mounted. Mounting $source at $target..."
  if [[ ! -d "$target" ]]; then
    sudo mkdir -p -- "$target"
  fi

  options="uid=$(id -u),gid=$(id -g),credentials=$credentials"
  [[ -z "$extra_options" ]] || options+=",$extra_options"
  timeout --foreground 30s sudo mount -t cifs "$source" "$target" -o "$options" \
    || die "Failed to mount $source at $target."
  is_mounted "$target" || die "Mount command completed but $target is not mounted."
}

mount_backup_share() {
  local match_host="$1"
  local mount_row mount_id mount_source share_host

  case "$(uname -s)" in
    Darwin)
      mount_row="$(runtime_mount_rows "$match_host" mac)"
      [[ -n "${mount_row//$'\n'/}" ]] || die "No SMB mount matches host '$match_host'."
      [[ "$mount_row" != *$'\n'* ]] || die "Several SMB mounts match host '$match_host'."
      IFS=$'\t' read -r mount_id mount_source <<< "$mount_row"
      share_name="$(backup_share_name "$mount_source")"
      share_host="$(backup_share_host "$mount_source")"
      scan_mount="$(find_mounted_share "$share_host" "$share_name")"
      if [[ -z "$scan_mount" ]]; then
        echo "Mount not found. Connecting [$mount_id]..."
        "${SCRIPT_DIR}/mount.sh" "$mount_id"
        scan_mount="$(find_mounted_share "$share_host" "$share_name")"
      fi
      ;;
    Linux)
      # shellcheck disable=SC1091
      source "${FORGE_ROOT}/linux/scripts/smb-credentials.sh"
      mount_row="$(runtime_mount_rows "$match_host" linux)"
      [[ -n "${mount_row//$'\n'/}" ]] || die "No SMB mount matches host '$match_host'."
      [[ "$mount_row" != *$'\n'* ]] || die "Several SMB mounts match host '$match_host'."
      IFS=$'\t' read -r mount_source mountpoint_raw credentials_chapter credentials_remote mount_options <<< "$mount_row"
      scan_mount="$(expand_home "$mountpoint_raw")"
      share_name="$(backup_share_name "$mount_source")"
      credentials_file="$(forge_smb_materialize_credentials "$credentials_chapter" "$credentials_remote")"
      trap 'rm -f -- "$credentials_file"' EXIT
      ensure_linux_mount "$mount_source" "$scan_mount" "$credentials_file" "$mount_options"
      ;;
    *)
      die "Unsupported operating system: $(uname -s)"
      ;;
  esac

  [[ -n "${scan_mount:-}" && -d "$scan_mount" ]] || die "SMB share for '$server_name' is not mounted."
  scan_dir="$(resolve_backup_scan_dir "$scan_mount" "$share_name" "$backup_dir")" \
    || die "Could not find backup path '$backup_dir' on $scan_mount."
}

file_size_bytes() {
  local file="$1"
  case "$(uname -s)" in
    Darwin) stat -f '%z' -- "$file" ;;
    Linux) stat -c '%s' -- "$file" ;;
  esac
}

# Returns 0 when name is a single file whose SMB path is a regular file of
# the same size SQL listed.
snapshot_target_ok() {
  local name="$1"
  local expected="$2"
  local target="$3"
  local actual

  if [[ "$name" == */* || "$name" == *\\* || "$name" == "." || "$name" == ".." ]]; then
    echo "   ✖ [$name] is not a single snapshot file name." >&2
    return 1
  fi
  if [[ -L "$target" ]]; then
    echo "   ✖ [$name] is a symlink at $target." >&2
    return 1
  fi
  if [[ ! -f "$target" ]]; then
    echo "   ✖ [$name] is not a file at $target." >&2
    return 1
  fi
  actual="$(file_size_bytes "$target")" || {
    echo "   ✖ [$name] size could not be read at $target." >&2
    return 1
  }
  if [[ "$actual" != "$expected" ]]; then
    echo "   ✖ [$name] size mismatch at $target: SMB ${actual} bytes, SQL ${expected} bytes." >&2
    return 1
  fi
  return 0
}

human_file_size() {
  local bytes="$1"
  local unit_index=0
  local unit_size=1
  local scaled_tenths
  local -a units=(B KiB MiB GiB TiB)

  while ((bytes >= unit_size * 1024 && unit_index < ${#units[@]} - 1)); do
    unit_size=$((unit_size * 1024))
    unit_index=$((unit_index + 1))
  done

  if ((unit_index == 0)); then
    printf '%d B' "$bytes"
    return
  fi

  scaled_tenths=$(((bytes * 10 + unit_size / 2) / unit_size))
  printf '%d.%d %s' "$((scaled_tenths / 10))" "$((scaled_tenths % 10))" "${units[$unit_index]}"
}

#######################################
# Select remote SQL target (same source as rdbsn / rdbr)
#######################################
selection_tsv="$(
  jq -r '
    (.remote_sql // [])
    | to_entries[]?
    | select(
        .value.name != null and
        .value.user != null and
        .value.pwd != null and
        .value.backuppath != null and
        ((.value.serverurl != null) or (.value.host != null))
      )
    | [
        (.key|tostring),
        .value.name,
        (.value.serverurl // ""),
        (.value.host // ""),
        (.value.port // ""),
        (.value.instance // ""),
        (.value.instance_strict // false),
        .value.user,
        .value.pwd,
        .value.backuppath
      ]
    | @tsv
  ' "$LOCAL_STORE_FILE"
)"

[[ -n "${selection_tsv//$'\n'/}" ]] || die "No valid entries under remote_sql in $LOCAL_STORE_FILE"

chosen_line="$(
  printf '%s\n' "$selection_tsv" \
    | fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=2,3,4,5,6,10 --height=65%
)" || die "No remote SQL target selected."

server_name="$(printf '%s' "$chosen_line" | cut -f2)"
server_url="$(printf '%s' "$chosen_line" | cut -f3)"
server_host="$(printf '%s' "$chosen_line" | cut -f4)"
server_port="$(printf '%s' "$chosen_line" | cut -f5)"
server_instance="$(printf '%s' "$chosen_line" | cut -f6)"
instance_strict_raw="$(printf '%s' "$chosen_line" | cut -f7)"
server_user="$(printf '%s' "$chosen_line" | cut -f8)"
server_pwd="$(printf '%s' "$chosen_line" | cut -f9)"
backup_dir="$(printf '%s' "$chosen_line" | cut -f10-)"

[[ -n "$server_user" && -n "$server_pwd" && -n "$backup_dir" ]] ||
  die "Selected remote_sql entry is missing required fields."

connect_server=""
expected_instance=""

if [[ -n "$server_host" ]]; then
  if [[ -n "$server_port" ]]; then
    connect_server="tcp:${server_host},${server_port}"
  elif [[ -n "$server_instance" ]]; then
    connect_server="${server_host}\\${server_instance}"
  else
    connect_server="$server_host"
  fi

  if [[ -n "$server_instance" ]]; then
    expected_instance="$server_instance"
  fi
else
  connect_server="$server_url"

  if [[ "$connect_server" == *,*\\* || "$connect_server" == *\\*,* ]]; then
    die "remote_sql entry '$server_name' has invalid serverurl '$connect_server'. Use structured fields host/port/instance instead."
  fi
fi

[[ -n "$connect_server" ]] || die "Selected remote_sql entry does not define a usable server address."

#######################################
# sqlcmd runners
#######################################
run_sqlcmd_raw() {
  if [[ -n "$SQLCMD_GODEBUG" ]]; then
    GODEBUG="$SQLCMD_GODEBUG" "$SQLCMD_BIN" "$@"
  else
    "$SQLCMD_BIN" "$@"
  fi
}

# Run a query, die on error, return raw rows (CR stripped, blank lines dropped).
run_q_rows() {
  local sep="$1" query="$2" out rc
  set +e
  out="$(
    run_sqlcmd_raw \
      -S "$connect_server" -U "$server_user" -P "$server_pwd" \
      -C -b -h -1 -W -s "$sep" -w 65535 \
      -Q "$query" 2>&1
  )"
  rc=$?
  set -e
  if ((rc != 0)); then
    die "SQL query failed on '$server_name' ($connect_server):"$'\n'"$(printf '%s' "$out" | tr -d '\r' | sed '/^$/d' | tail -n 12)"
  fi
  printf '%s' "$out" | tr -d '\r' | sed '/^$/d'
}

# Run a scalar query, return first non-empty value (may be empty).
run_q_scalar() {
  run_q_rows '|' "$1" | head -n 1
}

#######################################
# Verify instance (same guard as rdbsn / rdbr)
#######################################
if [[ -n "$expected_instance" ]]; then
  instance_actual="$(run_q_scalar "SET NOCOUNT ON; SELECT COALESCE(CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128)), N'MSSQLSERVER');")"
  [[ -n "$instance_actual" ]] || die "Connected, but could not read SQL instance name."

  if [[ "${instance_actual,,}" != "${expected_instance,,}" ]]; then
    if is_truthy "$instance_strict_raw"; then
      die "Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'."
    fi
    echo "⚠ Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'." >&2
    echo "  Continuing because instance_strict is false." >&2
  fi
fi

#######################################
# List .bak snapshots in backup_dir (size + name), newest first
#######################################
backup_dir_sql="$(escape_tsql_string "$backup_dir")"
dirlist_raw="$(run_q_rows '|' "SET NOCOUNT ON; SELECT CAST(size_in_bytes AS bigint), CONVERT(varchar(16), last_write_time, 120), file_or_directory_name FROM sys.dm_os_enumerate_filesystem(N'$backup_dir_sql', N'*.bak') WHERE is_directory = 0 ORDER BY last_write_time DESC;")"

# Join backup_dir + filename respecting path style.
join_backup_path() {
  local name="$1"
  if [[ "$backup_dir" == *'\'* && "$backup_dir" != */* ]]; then
    printf '%s\\%s' "${backup_dir%\\}" "$name"
  else
    printf '%s/%s' "${backup_dir%/}" "$name"
  fi
}

BACKUP_ROWS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  IFS='|' read -r size_bytes ts name <<< "$line"
  size_bytes="$(trim "$size_bytes")"
  ts="$(trim "$ts")"
  name="$(trim "$name")"
  [[ -n "$name" ]] || continue
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || continue
  case "${name,,}" in
    *.bak) ;;
    *) continue ;;
  esac
  [[ -n "$ts" ]] || ts="?"
  # display \t name \t bytes  (fzf shows only the display column)
  printf -v backup_row '%-16s  [%9s]  %s\t%s\t%s' "$ts" "$(human_file_size "$size_bytes")" "$name" "$name" "$size_bytes"
  BACKUP_ROWS+=("$backup_row")
done <<< "$dirlist_raw"

((${#BACKUP_ROWS[@]} > 0)) || die "No .bak files found in backup path on '$server_name': $backup_dir"

mapfile -t SELECTED_ROWS < <(
  printf '%s\n' "${BACKUP_ROWS[@]}" \
    | fzf --multi --delimiter=$'\t' --with-nth=1 \
          --prompt="Snapshot(s) on $server_name to DELETE > " \
          --header='TAB to mark multiple, ENTER to confirm selection' \
          --height=70% --reverse
)
((${#SELECTED_ROWS[@]} > 0)) || die "No snapshot selected."

SELECTED_NAMES=()
SELECTED_BYTES=()
for row in "${SELECTED_ROWS[@]}"; do
  name="$(printf '%s' "$row" | cut -f2)"
  bytes="$(printf '%s' "$row" | cut -f3)"
  [[ -n "$name" && "$bytes" =~ ^[0-9]+$ ]] || die "Unexpected snapshot selection."
  SELECTED_NAMES+=("$name")
  SELECTED_BYTES+=("$bytes")
done

#######################################
# Resolve the SMB path before asking to delete
#######################################
match_host="$server_host"
[[ -n "$match_host" ]] || match_host="$server_url"
mount_backup_share "$match_host"

preflight_failed=0
for i in "${!SELECTED_NAMES[@]}"; do
  if ! snapshot_target_ok "${SELECTED_NAMES[$i]}" "${SELECTED_BYTES[$i]}" "${scan_dir}/${SELECTED_NAMES[$i]}"; then
    preflight_failed=1
  fi
done
if ((preflight_failed != 0)); then
  die "Refusing to delete. The SMB file does not match the SQL listing. Nothing was deleted."
fi

#######################################
# Strict confirmation
#######################################
total_selected_bytes=0
echo
echo "⚠ You are about to PERMANENTLY DELETE these snapshot file(s) on the SMB share:"
for i in "${!SELECTED_NAMES[@]}"; do
  echo "    [$(human_file_size "${SELECTED_BYTES[$i]}")]  $(join_backup_path "${SELECTED_NAMES[$i]}")"
  echo "        SMB: ${scan_dir}/${SELECTED_NAMES[$i]}"
  total_selected_bytes=$((total_selected_bytes + SELECTED_BYTES[$i]))
done
echo "  Server: $server_name ($connect_server)"
[[ -n "$expected_instance" ]] && echo "  Instance: $expected_instance"
echo "  Total selected: $(human_file_size "$total_selected_bytes")"
echo
echo "Type 'delete' to confirm."
read -r -p "> " answer
[[ "$answer" == "delete" ]] || die "Confirmation mismatch. Aborted (nothing was deleted)."

#######################################
# Delete through the SMB share, then verify the file is gone
#######################################
freed_bytes=0
deleted_count=0
failed_count=0

for i in "${!SELECTED_NAMES[@]}"; do
  name="${SELECTED_NAMES[$i]}"
  bytes="${SELECTED_BYTES[$i]}"
  target="${scan_dir}/${name}"

  echo "-> Deleting [$name] at $target..."

  if ! snapshot_target_ok "$name" "$bytes" "$target"; then
    failed_count=$((failed_count + 1))
    continue
  fi

  set +e
  rm -f -- "$target"
  rm_rc=$?
  set -e

  if ((rm_rc == 0)) && [[ ! -e "$target" ]]; then
    freed_bytes=$((freed_bytes + bytes))
    deleted_count=$((deleted_count + 1))
  else
    failed_count=$((failed_count + 1))
    echo "   ✖ Could not delete [$name]." >&2
    echo "     The SMB share denied the delete." >&2
  fi
done

echo
if ((deleted_count > 0)); then
  echo "✔ Deleted $deleted_count snapshot(s) on $server_name. Space freed: $(human_file_size "$freed_bytes")."
fi
if ((failed_count > 0)); then
  die "$failed_count snapshot(s) could not be deleted (see messages above)."
fi
