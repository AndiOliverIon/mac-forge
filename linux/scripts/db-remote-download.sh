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

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/smb-credentials.sh"

credentials_file=""
transfer_log=""
cleanup_runtime_files() {
  [[ -z "${credentials_file:-}" ]] || rm -f -- "$credentials_file"
  [[ -z "${transfer_log:-}" ]] || rm -f -- "$transfer_log"
}
trap cleanup_runtime_files EXIT

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

is_mounted() {
  local target="$1"

  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$target"
  else
    findmnt -rn --target "$target" >/dev/null 2>&1
  fi
}

ensure_mount() {
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

  timeout --foreground 30s \
    sudo mount -t cifs "$source" "$target" -o "$options" \
    || die "Failed to mount $source at $target. Mount it manually with 'mnt' or check credentials."

  is_mounted "$target" || die "Mount command completed but $target is not mounted."
  echo "Mounted: $target"
}

require_cmd find
require_cmd fzf
require_cmd jq
require_cmd python3
require_cmd smbclient
require_cmd stat

# shellcheck disable=SC1091
source "${FORGE_ROOT}/scripts/backup-share-path.sh"

LOCAL_STORE_FILE="${FORGE_ROOT}/config-local/local-store.json"
[[ -f "$LOCAL_STORE_FILE" ]] || die "Missing local store file: $LOCAL_STORE_FILE"

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
[[ -n "${selection_tsv//$'\n'/}" ]] || die "No valid entries under remote_sql in $LOCAL_STORE_FILE."

chosen_line="$(
  printf '%s\n' "$selection_tsv" |
    fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=1,2,3,4,5,6 --height=65%
)" || die "No remote SQL target selected."

IFS=$'\t' read -r server_name server_host server_url _server_port _server_instance backup_dir <<< "$chosen_line"
match_host="$server_host"
[[ -n "$match_host" ]] || match_host="$server_url"
[[ -n "$match_host" && -n "$backup_dir" ]] || die "Selected remote_sql entry is missing a host or backup path."

mount_row="$(runtime_mount_rows "$match_host" linux)"
[[ -n "${mount_row//$'\n'/}" ]] || die "No SMB mount in $RUNTIME_CONFIG_FILE matches host '$match_host'."
[[ "$mount_row" != *$'\n'* ]] || die "Several SMB mounts match host '$match_host'."

IFS=$'\t' read -r smb_source mountpoint_raw credentials_chapter credentials_remote mount_options <<< "$mount_row"
mountpoint="${RDOWN_MOUNT_PATH:-$(expand_home "$mountpoint_raw")}"
share_name="$(backup_share_name "$smb_source")"
credentials_file="$(forge_smb_materialize_cifs_credentials "$credentials_chapter" "$credentials_remote")"

ensure_mount "$smb_source" "$mountpoint" "$credentials_file" "$mount_options"

scan_dir="$(resolve_backup_scan_dir "$mountpoint" "$share_name" "$backup_dir")" \
  || die "Could not find backup path '$backup_dir' on $mountpoint."

echo "Scanning backups for $server_name"
echo "  Path: $scan_dir"

mapfile -t backup_list < <(
  find "$scan_dir" -maxdepth 2 -type f \( -iname '*.bak' -o -iname '*.bkp' \) \
    -printf '%T@\t%p\0' \
    | sort -zrn \
    | cut -z -f2- \
    | tr '\0' '\n'
)

((${#backup_list[@]} > 0)) || die "No .bak or .bkp files found in $scan_dir."

backup_rows=()
for backup_full in "${backup_list[@]}"; do
  backup_rel="${backup_full#"$mountpoint"/}"
  display_rel="${backup_full#"$scan_dir"/}"
  size_bytes="$(stat -c '%s' -- "$backup_full")" || continue
  printf -v backup_row '[%9s]  %s\t%s' "$(human_file_size "$size_bytes")" "$display_rel" "$backup_rel"
  backup_rows+=("$backup_row")
done

((${#backup_rows[@]} > 0)) || die "No backup metadata could be read from $scan_dir."

selected_row="$(
  printf '%s\n' "${backup_rows[@]}" \
    | fzf --prompt="Select backup from $server_name > " --delimiter=$'\t' --with-nth=1 --height=70% --reverse
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
transfer_log=""

echo
echo "Transfer complete: $target_full"
