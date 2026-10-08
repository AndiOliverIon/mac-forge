#!/usr/bin/env bash
# vps1-db-relay-download.sh — relay a remote .bak straight from that
# connection's SMB backup path to the vps1 snapshots folder, without landing
# it on the local SSD.
#
# The remote target is chosen the same way as rdown: one remote_sql entry,
# then the .bak/.bkp files in that entry's backup path.
#
#     SMB backup path  --rsync over ssh-->  vps1:snapshots
#
# rsync reads blocks from the mounted share and writes them to vps1 over ssh.
# No intermediate .bak is written to local disk.
#
# Use after `rdbsn` has created the backup on the remote server. Restore on vps1
# afterwards with `v1r`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

die() { vps1_die "$@"; }
require_cmd() { vps1_require_cmd "$@"; }

require_cmd fzf
require_cmd jq
require_cmd python3
require_cmd rsync
require_cmd ssh
require_cmd stat

# shellcheck disable=SC1091
source "$VPS1_REPO_ROOT/scripts/backup-share-path.sh"

FORGE_ROOT="$VPS1_REPO_ROOT"
LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$VPS1_REPO_ROOT/config-local}/local-store.json"
RUNTIME_CONFIG_FILE="$VPS1_REPO_ROOT/linux/config/runtime.json"
[[ -f "$LOCAL_STORE_FILE" ]] || vps1_die "Missing local store file: $LOCAL_STORE_FILE"
[[ -f "$RUNTIME_CONFIG_FILE" ]] || vps1_die "Missing runtime config: $RUNTIME_CONFIG_FILE"

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) vps1_die "Unsupported operating system: $(uname -s)" ;;
esac

credentials_file=""
cleanup_credentials() {
  [[ -z "${credentials_file:-}" ]] || rm -f -- "$credentials_file"
}
trap cleanup_credentials EXIT

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

is_mounted() {
  local target="$1"

  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$target"
  else
    findmnt -rn --target "$target" >/dev/null 2>&1
  fi
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

  timeout --foreground 30s \
    sudo mount -t cifs "$source" "$target" -o "$options" \
    || vps1_die "Failed to mount $source at $target. Mount it manually with 'mnt' or check credentials."

  is_mounted "$target" || vps1_die "Mount command completed but $target is not mounted."
  echo "Mounted: $target"
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

[[ -n "${selection_tsv//$'\n'/}" ]] || vps1_die "No valid entries under remote_sql in $LOCAL_STORE_FILE"

chosen_line="$(
  printf '%s\n' "$selection_tsv" |
    fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=1,2,3,4,5,6 --height=65%
)" || vps1_die "No remote SQL target selected."

server_name="$(printf '%s' "$chosen_line" | cut -f1)"
server_host="$(printf '%s' "$chosen_line" | cut -f2)"
server_url="$(printf '%s' "$chosen_line" | cut -f3)"
backup_dir="$(printf '%s' "$chosen_line" | cut -f6-)"
match_host="$server_host"
[[ -n "$match_host" ]] || match_host="$server_url"
[[ -n "$match_host" && -n "$backup_dir" ]] || vps1_die "Selected remote_sql entry is missing a host or backup path."

case "$(uname -s)" in
  Darwin)
    mount_row="$(runtime_mount_rows "$match_host" mac)"
    [[ -n "${mount_row//$'\n'/}" ]] || vps1_die "No SMB mount in $RUNTIME_CONFIG_FILE matches host '$match_host'."
    [[ "$mount_row" != *$'\n'* ]] || vps1_die "Several SMB mounts match host '$match_host'."
    IFS=$'\t' read -r mount_id mount_source <<< "$mount_row"
    share_name="$(backup_share_name "$mount_source")"
    share_host="$(backup_share_host "$mount_source")"
    scan_mount="$(find_mounted_share "$share_host" "$share_name")"
    if [[ -z "$scan_mount" ]]; then
      echo "📡 Mount not found. Connecting [$mount_id]..."
      "$VPS1_REPO_ROOT/scripts/mount.sh" "$mount_id"
      scan_mount="$(find_mounted_share "$share_host" "$share_name")"
    fi
    ;;
  Linux)
    # shellcheck disable=SC1091
    source "$VPS1_REPO_ROOT/linux/scripts/smb-credentials.sh"
    mount_row="$(runtime_mount_rows "$match_host" linux)"
    [[ -n "${mount_row//$'\n'/}" ]] || vps1_die "No SMB mount in $RUNTIME_CONFIG_FILE matches host '$match_host'."
    [[ "$mount_row" != *$'\n'* ]] || vps1_die "Several SMB mounts match host '$match_host'."
    IFS=$'\t' read -r mount_source mountpoint_raw credentials_chapter credentials_remote mount_options <<< "$mount_row"
    scan_mount="${RDOWN_MOUNT_PATH:-$(expand_home "$mountpoint_raw")}"
    share_name="$(backup_share_name "$mount_source")"
    credentials_file="$(forge_smb_materialize_credentials "$credentials_chapter" "$credentials_remote")"
    ensure_linux_mount "$mount_source" "$scan_mount" "$credentials_file" "$mount_options"
    ;;
esac

[[ -n "${scan_mount:-}" && -d "$scan_mount" ]] || vps1_die "SMB share for '$server_name' is not mounted."
scan_dir="$(resolve_backup_scan_dir "$scan_mount" "$share_name" "$backup_dir")" \
  || vps1_die "Could not find backup path '$backup_dir' on $scan_mount."

#######################################
# Pick backup from the connection path
#######################################
echo "🔍 Scanning backups for $server_name"
echo "   Path: $scan_dir"

if [[ "$(uname -s)" == Darwin ]]; then
  mapfile -t BACKUP_LIST < <(
    find "$scan_dir" -maxdepth 2 -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print0 |
      xargs -0 stat -f '%m%t%N' |
      sort -nr |
      cut -f2-
  )
else
  mapfile -t BACKUP_LIST < <(
    find "$scan_dir" -maxdepth 2 -type f \( -iname '*.bak' -o -iname '*.bkp' \) \
      -printf '%T@\t%p\0' |
      sort -zrn |
      cut -z -f2- |
      tr '\0' '\n'
  )
fi

((${#BACKUP_LIST[@]} > 0)) || vps1_die "No .bak files found in $scan_dir."

BACKUP_ROWS=()
for backup_full in "${BACKUP_LIST[@]}"; do
  [[ -f "$backup_full" ]] || continue
  backup_rel="${backup_full#"$scan_dir"/}"
  size_bytes="$(file_size_bytes "$backup_full")" || continue
  printf -v backup_row '[%9s]  %s\t%s' "$(human_file_size "$size_bytes")" "$backup_rel" "$backup_full"
  BACKUP_ROWS+=("$backup_row")
done

((${#BACKUP_ROWS[@]} > 0)) || vps1_die "No readable .bak files found in $scan_dir."

SELECTED_ROW="$(
  printf '%s\n' "${BACKUP_ROWS[@]}" |
    fzf --prompt="Select backup from $server_name to relay to vps1 > " --delimiter=$'\t' --with-nth=1 --height=70% --reverse
)" || vps1_die "No backup selected."
[[ "$SELECTED_ROW" == *$'\t'* ]] || vps1_die "Unexpected backup selection."
SOURCE_FULL="${SELECTED_ROW#*$'\t'}"
name="$(basename "$SOURCE_FULL")"

#######################################
# Stream share -> vps1 (no local SSD write)
#######################################
echo
echo "🚀 Relaying snapshot to vps1 (no local copy)"
echo "   Source      : $SOURCE_FULL"
echo "   Destination : ${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${name}"
echo

# --no-perms/--no-owner/--no-group avoids SMB ownership/permission warnings on
# the source; vps1_chmod_snapshot fixes container-readable perms afterwards.
rsync -h --progress --no-perms --no-owner --no-group \
  -e "ssh -o ConnectTimeout=$VPS1_SSH_CONNECT_TIMEOUT" \
  "$SOURCE_FULL" \
  "${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/"

# Ensure SQL Server (container mssql uid) can read the uploaded file.
vps1_chmod_snapshot "$name"

vps1_ssh "test -f '$VPS1_SNAPSHOTS_HOST_DIR/$name'" \
  || vps1_die "Relay reported success but file not found on vps1: $VPS1_SNAPSHOTS_HOST_DIR/$name"

echo
echo "✔ Relay complete: ${VPS1_SNAPSHOTS_HOST_DIR}/${name}"
echo "  Restore it on vps1 with:  v1r"
