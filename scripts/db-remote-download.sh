#!/usr/bin/env bash
set -euo pipefail

#######################################
# Load forge config
#######################################
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
require_cmd python3
require_cmd rsync
require_cmd stat

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/backup-share-path.sh"

LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$HOME/mac-forge/config-local}/local-store.json"
RUNTIME_CONFIG_FILE="${FORGE_ROOT:-$HOME/mac-forge}/linux/config/runtime.json"
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

file_size_bytes() {
  case "$(uname -s)" in
    Darwin) stat -f '%z' -- "$1" ;;
    Linux) stat -c '%s' -- "$1" ;;
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

mount_row="$(runtime_mount_rows "$match_host" mac)"
[[ -n "${mount_row//$'\n'/}" ]] || die "No SMB mount in $RUNTIME_CONFIG_FILE matches host '$match_host'."
[[ "$mount_row" != *$'\n'* ]] || die "Several SMB mounts match host '$match_host'."

IFS=$'\t' read -r mount_id mount_source <<< "$mount_row"
share_name="$(backup_share_name "$mount_source")"
share_host="$(backup_share_host "$mount_source")"
scan_mount="$(find_mounted_share "$share_host" "$share_name")"
if [[ -z "$scan_mount" ]]; then
  echo "📡 Mount not found. Connecting [$mount_id]..."
  "${SCRIPT_DIR}/mount.sh" "$mount_id"
  scan_mount="$(find_mounted_share "$share_host" "$share_name")"
fi
[[ -n "$scan_mount" && -d "$scan_mount" ]] || die "SMB share for '$server_name' is not mounted."

scan_dir="$(resolve_backup_scan_dir "$scan_mount" "$share_name" "$backup_dir")" \
  || die "Could not find backup path '$backup_dir' on $scan_mount."

#######################################
# Step 1 — Pick Backup from the connection path
#######################################
echo "🔍 Scanning backups for $server_name"
echo "   Path: $scan_dir"

mapfile -t BACKUP_LIST < <(
  find "$scan_dir" -maxdepth 2 -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print0 |
    xargs -0 stat -f '%m%t%N' |
    sort -nr |
    cut -f2-
)

((${#BACKUP_LIST[@]} > 0)) || die "No .bak files found in $scan_dir."

BACKUP_ROWS=()
for backup_full in "${BACKUP_LIST[@]}"; do
  [[ -f "$backup_full" ]] || continue
  backup_rel="${backup_full#"$scan_dir"/}"
  size_bytes="$(file_size_bytes "$backup_full")" || continue
  printf -v backup_row '[%9s]  %s\t%s' "$(human_file_size "$size_bytes")" "$backup_rel" "$backup_full"
  BACKUP_ROWS+=("$backup_row")
done

((${#BACKUP_ROWS[@]} > 0)) || die "No readable .bak files found in $scan_dir."

SELECTED_ROW="$(
  printf '%s\n' "${BACKUP_ROWS[@]}" |
    fzf --prompt="Select backup from $server_name > " --delimiter=$'\t' --with-nth=1 --height=70% --reverse
)" || die "No backup selected."
[[ "$SELECTED_ROW" == *$'\t'* ]] || die "Unexpected backup selection."
SOURCE_FULL="${SELECTED_ROW#*$'\t'}"

#######################################
# Step 2 — Pick Local Destination
#######################################
: "${FORGE_WORK_STATE_FILE:?FORGE_WORK_STATE_FILE must be set by forge.sh}"
dest_tsv="$(
  jq -r '
    ."download-destinations" // []
    | .[]
    | select(.title != null and .path != null)
    | [.title, .path] | @tsv
  ' "$FORGE_WORK_STATE_FILE"
)"

[[ -n "${dest_tsv//$'\n'/}" ]] || die "No download-destinations found in: $FORGE_WORK_STATE_FILE"

chosen_dest_line="$(
  printf '%s\n' "$dest_tsv" \
    | fzf --prompt='Download Destination > ' --delimiter=$'\t' --with-nth=1,2 --height=40%
)" || die "No destination selected."

dest_title="$(printf '%s' "$chosen_dest_line" | cut -f1)"
dest_path_raw="$(printf '%s' "$chosen_dest_line" | cut -f2-)"

dest_path="$(expand_home "$dest_path_raw")"

[[ -d "$dest_path" ]] || mkdir -p "$dest_path"

#######################################
# Step 3 — Transfer with progress
#######################################
FILENAME="$(basename "$SOURCE_FULL")"
TARGET_FULL="${dest_path}/${FILENAME}"

echo
echo "🚀 Transferring Backup"
echo "   Source      : $SOURCE_FULL"
echo "   Destination : [$dest_title] $TARGET_FULL"
echo

rsync -ah --progress "$SOURCE_FULL" "$TARGET_FULL"

echo
echo "✔ Transfer complete: $TARGET_FULL"
