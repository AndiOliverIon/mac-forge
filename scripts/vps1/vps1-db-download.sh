#!/opt/homebrew/bin/bash
# vps1-db-download.sh — download a .bak from the dedicated vps1 snapshots folder
# to a local directory.
#
# Usage: vps1-db-download.sh [destination-dir]
#        (default destination: ~/sql/snapshots, override via VPS1_DOWNLOAD_DIR)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd fzf
vps1_require_cmd ssh
vps1_require_cmd rsync

#######################################
# Destination
#######################################
DEST_DIR="${1:-${VPS1_DOWNLOAD_DIR:-$HOME/sql/snapshots}}"
mkdir -p "$DEST_DIR"
[[ -d "$DEST_DIR" && -w "$DEST_DIR" ]] || vps1_die "Destination not writable: $DEST_DIR"

#######################################
# Pick a .bak from the vps1 snapshots folder
#######################################
mapfile -t BAKS < <(vps1_list_snapshots)
((${#BAKS[@]} > 0)) || vps1_die "No .bak files in vps1 snapshots dir: $VPS1_SNAPSHOTS_HOST_DIR"

selected="$(printf '%s\n' "${BAKS[@]}" | fzf --prompt='Select vps1 .bak to download > ' --height=60% --reverse)" \
  || vps1_die "No file selected."

#######################################
# Transfer
#######################################
echo
echo "🚀 Downloading vps1 snapshot"
echo "   Source      : ${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${selected}"
echo "   Destination : ${DEST_DIR}/${selected}"
echo

rsync -ah --progress \
  -e "ssh -o ConnectTimeout=$VPS1_SSH_CONNECT_TIMEOUT" \
  "${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${selected}" \
  "${DEST_DIR}/"

echo
echo "✔ Download complete: ${DEST_DIR}/${selected}"
