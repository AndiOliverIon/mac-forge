#!/usr/bin/env bash
# db-remote-list.sh (alias: rlist)
#
# Choose a remote SQL target the same way as rdown and rdbsn, then print the
# snapshots in that target's backup path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
fi

die() { echo "✖ $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) die "rlist runs on macOS and Linux. This station reported $(uname -s)." ;;
esac
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

require_cmd find
require_cmd fzf
require_cmd jq
require_cmd python3
require_cmd stat

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/backup-share-path.sh"

LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$FORGE_ROOT/config-local}/local-store.json"
RUNTIME_CONFIG_FILE="${FORGE_ROOT}/linux/config/runtime.json"
[[ -f "$LOCAL_STORE_FILE" ]] || die "Missing local store file: $LOCAL_STORE_FILE"
[[ -f "$RUNTIME_CONFIG_FILE" ]] || die "Missing runtime config: $RUNTIME_CONFIG_FILE"

expand_home() {
  local path="$1"

  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#"~/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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

file_stamp() {
  local file="$1"

  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%m%t%Sm%t%z' -t '%Y-%m-%d %H:%M' -- "$file"
  else
    stat -c '%Y%t%y%t%s' -- "$file" | awk -F '\t' '{ printf "%s\t%s\t%s\n", $1, substr($2, 1, 16), $3 }'
  fi
}

print_snapshots() {
  local scan_dir="$1"
  local -a rows=()
  local file stamp sortkey modified bytes

  while IFS= read -r -d '' file; do
    stamp="$(file_stamp "$file")"
    IFS=$'\t' read -r sortkey modified bytes <<< "$stamp"
    rows+=("${sortkey}"$'\t'"${file#"$scan_dir"/}"$'\t'"${modified}"$'\t'"${bytes}")
  done < <(find "$scan_dir" -maxdepth 2 -type f \( -iname '*.bak' -o -iname '*.bkp' \) -print0)

  if ((${#rows[@]} == 0)); then
    echo "  (none)"
    return
  fi

  printf '  %-72s %-16s %10s\n' "FILE" "MODIFIED" "SIZE"
  printf '  %-72s %-16s %10s\n' "------------------------------------------------------------------------" "----------------" "----------"
  printf '%s\n' "${rows[@]}" | sort -nr | while IFS=$'\t' read -r _ rel modified bytes; do
    printf '  %-72s %-16s %10s\n' "$rel" "$modified" "$(human_file_size "$bytes")"
  done
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
        .value.name,
        (.value.host // ""),
        (.value.serverurl // ""),
        (.value.port // ""),
        (.value.instance // ""),
        .value.backuppath
      ]
    | @tsv
  ' "$LOCAL_STORE_FILE"
)"
[[ -n "${selection_tsv//$'\n'/}" ]] || die "No valid entries under remote_sql in $LOCAL_STORE_FILE"

chosen_line="$(
  printf '%s\n' "$selection_tsv" |
    fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=1,2,3,4,5,6 --height=65%
)" || die "No remote SQL target selected."

server_name="$(printf '%s' "$chosen_line" | cut -f1)"
server_host="$(printf '%s' "$chosen_line" | cut -f2)"
server_url="$(printf '%s' "$chosen_line" | cut -f3)"
backup_dir="$(printf '%s' "$chosen_line" | cut -f6-)"
match_host="$server_host"
[[ -n "$match_host" ]] || match_host="$server_url"
[[ -n "$match_host" && -n "$backup_dir" ]] || die "Selected remote_sql entry is missing a host or backup path."

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

[[ -n "$scan_mount" && -d "$scan_mount" ]] || die "SMB share for '$server_name' is not mounted."
scan_dir="$(resolve_backup_scan_dir "$scan_mount" "$share_name" "$backup_dir")" \
  || die "Could not find backup path '$backup_dir' on $scan_mount."

echo
echo "Snapshots for $server_name"
echo "  Backup path: $backup_dir"
echo "  Folder: $scan_dir"
echo
print_snapshots "$scan_dir"
echo
