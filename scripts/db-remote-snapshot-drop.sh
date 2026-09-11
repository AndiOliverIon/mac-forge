#!/opt/homebrew/bin/bash
# db-remote-snapshot-drop.sh (alias: rdbsndrop)
#
# Delete .bak snapshot file(s) from a configured remote SQL Server target's
# backup path (the stored backups, NOT the live databases). Mirrors
# db-remote-backup.sh (rdbsn) / db-remote-restore.sh (rdbr) for server
# selection, then:
#   1. lists .bak snapshots in the server's backup path (with size shown),
#   2. lets you multi-select which ones to delete (TAB to mark),
#   3. requires typing 'delete' to confirm,
#   4. removes them on the server via master.sys.xp_delete_files,
#   5. reports how much space was freed.
#
# Safety: nothing is deleted until you type 'delete'. Only files whose
# post-delete existence check confirms removal count toward "space freed".
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
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

require_cmd fzf
require_cmd jq
require_cmd sqlcmd

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
# Strict confirmation
#######################################
total_selected_bytes=0
echo
echo "⚠ You are about to PERMANENTLY DELETE these snapshot file(s) on the remote server:"
for i in "${!SELECTED_NAMES[@]}"; do
  echo "    [$(human_file_size "${SELECTED_BYTES[$i]}")]  $(join_backup_path "${SELECTED_NAMES[$i]}")"
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
# Delete + verify, tallying freed space
#######################################
freed_bytes=0
deleted_count=0
failed_count=0

for i in "${!SELECTED_NAMES[@]}"; do
  name="${SELECTED_NAMES[$i]}"
  bytes="${SELECTED_BYTES[$i]}"
  full_path="$(join_backup_path "$name")"
  full_path_sql="$(escape_tsql_string "$full_path")"

  echo "-> Deleting [$name] on $server_name..."

  set +e
  del_out="$(
    run_sqlcmd_raw \
      -S "$connect_server" -U "$server_user" -P "$server_pwd" \
      -C -b <<SQL_EOF 2>&1
SET NOCOUNT ON;
BEGIN TRY
  EXEC master.sys.xp_delete_files N'$full_path_sql';
END TRY
BEGIN CATCH
  PRINT CONCAT('DELETE FAILED (', ERROR_NUMBER(), '): ', ERROR_MESSAGE());
  THROW;
END CATCH
SQL_EOF
  )"
  del_rc=$?
  set -e

  # Verify the file is actually gone before counting it as freed space.
  still_exists="$(run_q_scalar "SET NOCOUNT ON; DECLARE @e int; EXEC master.dbo.xp_fileexist N'$full_path_sql', @e OUTPUT; SELECT @e;")"

  if ((del_rc == 0)) && [[ "$still_exists" != "1" ]]; then
    freed_bytes=$((freed_bytes + bytes))
    deleted_count=$((deleted_count + 1))
  else
    failed_count=$((failed_count + 1))
    echo "   ✖ Could not delete [$name]." >&2
    msg="$(printf '%s' "$del_out" | tr -d '\r' | sed '/^$/d' | tail -n 4)"
    [[ -n "$msg" ]] && printf '     %s\n' "$msg" >&2
  fi
done

echo
if ((deleted_count > 0)); then
  echo "✔ Deleted $deleted_count snapshot(s) on $server_name. Space freed: $(human_file_size "$freed_bytes")."
fi
if ((failed_count > 0)); then
  die "$failed_count snapshot(s) could not be deleted (see messages above)."
fi
