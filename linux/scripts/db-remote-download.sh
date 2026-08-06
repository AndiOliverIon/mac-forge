#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_CONFIG_FILE="${FORGE_ROOT}/linux/config/runtime.json"
WORK_STATE_FILE="${FORGE_ROOT}/configs/work-state.json"

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

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

smbclient_escape() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s\n' "$value"
}

require_cmd find
require_cmd fzf
require_cmd jq
require_cmd smbclient
require_cmd stat

mount_row="$(
  jq -r '
    .mounts // []
    | map(select(.id == "ardis-sql-backups"))
    | first
    | select(.source and .mountpoint and .credentials_file)
    | [.source, .mountpoint, .credentials_file]
    | @tsv
  ' "$RUNTIME_CONFIG_FILE"
)"
[[ -n "$mount_row" ]] || die "Mount 'ardis-sql-backups' is not configured in $RUNTIME_CONFIG_FILE."

IFS=$'\t' read -r smb_source mountpoint_raw credentials_raw <<< "$mount_row"
mountpoint="${RDOWN_MOUNT_PATH:-$(expand_home "$mountpoint_raw")}"
credentials_file="${RDOWN_CREDENTIALS_FILE:-$(expand_home "$credentials_raw")}"

[[ -f "$credentials_file" ]] || die "Credentials file not found: $credentials_file"
[[ -d "$mountpoint" ]] || die "Share is not mounted at $mountpoint. Run 'mnt' first."

echo "Scanning backups on $mountpoint..."

mapfile -t backup_list < <(
  find "$mountpoint" -maxdepth 2 -type f \( -iname '*.bak' -o -iname '*.bkp' \) \
    -printf '%T@\t%P\0' \
    | sort -zrn \
    | cut -z -f2- \
    | tr '\0' '\n'
)

((${#backup_list[@]} > 0)) || die "No .bak or .bkp files found on the share."

backup_rows=()
for backup_rel in "${backup_list[@]}"; do
  backup_full="${mountpoint}/${backup_rel}"
  size_bytes="$(stat -c '%s' -- "$backup_full")" || continue
  printf -v backup_row '[%9s]  %s\t%s' "$(human_file_size "$size_bytes")" "$backup_rel" "$backup_rel"
  backup_rows+=("$backup_row")
done

((${#backup_rows[@]} > 0)) || die "No backup metadata could be read from the share."

selected_row="$(
  printf '%s\n' "${backup_rows[@]}" \
    | fzf --prompt='Select backup from share > ' --delimiter=$'\t' --with-nth=1 --height=70% --reverse
)" || die "No backup selected."
[[ "$selected_row" == *$'\t'* ]] || die "Unexpected backup selection."
selected_rel="${selected_row#*$'\t'}"
expected_size="$(stat -c '%s' -- "${mountpoint}/${selected_rel}")" \
  || die "Could not read backup size: $selected_rel"
((expected_size > 0)) || die "Selected backup is empty: $selected_rel"

dest_rows="$(
  jq -r '
    ."download-destinations" // []
    | .[]
    | select(.title and .path)
    | [.title, .path]
    | @tsv
  ' "$WORK_STATE_FILE"
)"
[[ -n "${dest_rows//$'\n'/}" ]] || die "No download destinations found in $WORK_STATE_FILE."

selected_dest="$(
  printf '%s\n' "$dest_rows" \
    | fzf --prompt='Download destination > ' --delimiter=$'\t' --with-nth=1,2 --height=40%
)" || die "No destination selected."

IFS=$'\t' read -r dest_title dest_path_raw <<< "$selected_dest"
dest_path="$(expand_home "$dest_path_raw")"
mkdir -p -- "$dest_path"

filename="$(basename -- "$selected_rel")"
target_full="${dest_path}/${filename}"
partial_full="${target_full}.part"
remote_escaped="$(smbclient_escape "$selected_rel")"
partial_escaped="$(smbclient_escape "$partial_full")"

echo
echo "Transferring backup through authenticated Samba client"
echo "  Source      : ${smb_source}/${selected_rel}"
echo "  Destination : [$dest_title] $target_full"
echo

transfer_log="$(mktemp)"
trap 'rm -f -- "$transfer_log"' EXIT

printf 'reget "%s" "%s"\n' "$remote_escaped" "$partial_escaped" \
  | smbclient "$smb_source" -A "$credentials_file" >"$transfer_log" 2>&1 &
transfer_pid=$!
previous_size=0

if [[ -f "$partial_full" ]]; then
  previous_size="$(stat -c '%s' -- "$partial_full")"
fi

while kill -0 "$transfer_pid" 2>/dev/null; do
  current_size=0
  if [[ -f "$partial_full" ]]; then
    current_size="$(stat -c '%s' -- "$partial_full")"
  fi

  percent_tenths=$((current_size * 1000 / expected_size))
  ((percent_tenths > 1000)) && percent_tenths=1000
  bytes_per_second=$((current_size - previous_size))
  ((bytes_per_second < 0)) && bytes_per_second=0

  printf '\r  Progress : %3d.%d%%  %s / %s  %s/s    ' \
    "$((percent_tenths / 10))" \
    "$((percent_tenths % 10))" \
    "$(human_file_size "$current_size")" \
    "$(human_file_size "$expected_size")" \
    "$(human_file_size "$bytes_per_second")"

  previous_size="$current_size"
  sleep 1
done

if wait "$transfer_pid"; then
  transfer_status=0
else
  transfer_status=$?
fi

printf '\r\033[K'

if ((transfer_status != 0)); then
  cat "$transfer_log" >&2
  die "Samba transfer failed with exit code $transfer_status."
fi

if [[ ! -f "$partial_full" ]]; then
  cat "$transfer_log" >&2
  die "Samba did not create the download file. Check the NT_STATUS error above and verify the SMB username used on macOS."
fi
actual_size="$(stat -c '%s' -- "$partial_full")"
if [[ "$actual_size" -ne "$expected_size" ]]; then
  cat "$transfer_log" >&2
  die "Transfer is incomplete (${actual_size}/${expected_size} bytes). Resume it by running rdown again; partial file retained: $partial_full"
fi
mv -f -- "$partial_full" "$target_full"
rm -f -- "$transfer_log"
trap - EXIT

echo
echo "Transfer complete: $target_full"
