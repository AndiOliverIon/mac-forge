#!/opt/homebrew/bin/bash
# vps1-db-relay-download.sh — relay a remote .bak straight from the portainer
# SMB share to the vps1 snapshots folder, WITHOUT landing it on the Mac SSD.
#
# This collapses the old `rdown` (share -> local) + `v1up` (local -> vps1) into a
# single streaming hop:
#
#     SMB mount (/Volumes/shared-files)  --rsync over ssh-->  vps1:snapshots
#
# rsync reads blocks from the network-backed SMB mount and writes them to vps1
# over ssh; no intermediate .bak is written to the Mac's local disk. The only
# local buffering is OS-level SMB read cache in RAM, so this performs zero SSD
# writes for the transfer.
#
# Use after `rdbsn` has created the backup on the remote server. Restore on vps1
# afterwards with `v1r`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd fzf
vps1_require_cmd rsync
vps1_require_cmd ssh

#######################################
# Share / mount config (mirrors db-remote-download.sh)
#######################################
MOUNT_PATH="/Volumes/shared-files"
SMB_URL="smb://portainer.ardis.eu/shared-files"
MOUNT_WAIT_SECONDS="${RDOWN_MOUNT_WAIT_SECONDS:-120}"
MOUNT_RECHECK_SECONDS="${RDOWN_MOUNT_RECHECK_SECONDS:-2}"

[[ "$MOUNT_WAIT_SECONDS" =~ ^[0-9]+$ && "$MOUNT_WAIT_SECONDS" -gt 0 ]] || vps1_die "RDOWN_MOUNT_WAIT_SECONDS must be a positive integer."
[[ "$MOUNT_RECHECK_SECONDS" =~ ^[0-9]+$ && "$MOUNT_RECHECK_SECONDS" -gt 0 ]] || vps1_die "RDOWN_MOUNT_RECHECK_SECONDS must be a positive integer."

is_mount_ready() {
  [[ -d "$MOUNT_PATH" ]] || return 1
  mount | grep -F " on $MOUNT_PATH " >/dev/null 2>&1
}

wait_for_mount() {
  local elapsed=0

  echo "⏳ Waiting up to ${MOUNT_WAIT_SECONDS}s for mount at $MOUNT_PATH."
  echo "   If macOS asks for credentials, complete that prompt and this will continue."

  while ((elapsed < MOUNT_WAIT_SECONDS)); do
    if is_mount_ready; then
      echo "✔ Mount ready."
      return 0
    fi

    sleep "$MOUNT_RECHECK_SECONDS"
    elapsed=$((elapsed + MOUNT_RECHECK_SECONDS))
    echo "   Rechecking mount... ${elapsed}s"
  done

  return 1
}

if ! is_mount_ready; then
  echo "📡 Mount not found. Attempting to connect to $SMB_URL..."
  open "$SMB_URL"
  wait_for_mount || vps1_die "Failed to mount $MOUNT_PATH. Please check your connection or connect manually in Finder once."
fi

#######################################
# Pick backup from the share
#######################################
echo "🔍 Scanning backups on $MOUNT_PATH..."

mapfile -t BACKUP_LIST < <(
  find "$MOUNT_PATH" -maxdepth 2 -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print0 |
  xargs -0 ls -t |
  sed "s|^$MOUNT_PATH/||"
)

((${#BACKUP_LIST[@]} > 0)) || vps1_die "No .bak files found on the share."

SELECTED_REL="$(
  printf '%s\n' "${BACKUP_LIST[@]}" | fzf --prompt="Select backup to relay to vps1 > " --height=70% --reverse
)" || vps1_die "No backup selected."

SOURCE_FULL="$MOUNT_PATH/$SELECTED_REL"
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
