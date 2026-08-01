#!/usr/bin/env bash
# vps1-db-download.sh — download .bak files from the dedicated vps1 snapshots
# folder to a local directory. Multiple selections are downloaded concurrently
# and packaged as snapshot-YYYY-MM-DD-HHMMSS.zip.
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

selected="$(printf '%s\n' "${BAKS[@]}" | fzf --multi --prompt='Select vps1 .bak file(s) to download (Tab selects) > ' --height=60% --reverse)" \
  || vps1_die "No file selected."
[[ -n "$selected" ]] || vps1_die "No file selected."
mapfile -t SELECTED <<< "$selected"

#######################################
# Transfer
#######################################
if ((${#SELECTED[@]} == 1)); then
  selected="${SELECTED[0]}"

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
  exit 0
fi

vps1_require_cmd zip

archive_name="snapshot-$(date +%Y-%m-%d-%H%M%S).zip"
archive_path="${DEST_DIR}/${archive_name}"

staging_dir="$(mktemp -d "${DEST_DIR}/.v1down.XXXXXX")"
cleanup() { rm -rf -- "$staging_dir"; }
trap cleanup EXIT

echo
echo "🚀 Downloading ${#SELECTED[@]} vps1 snapshots concurrently"
echo "   Destination : ${archive_path}"
echo

pids=()
for selected in "${SELECTED[@]}"; do
  rsync -ah --progress \
    -e "ssh -o ConnectTimeout=$VPS1_SSH_CONNECT_TIMEOUT" \
    "${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${selected}" \
    "${staging_dir}/" &
  pids+=("$!")
done

transfer_failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || transfer_failed=1
done
((transfer_failed == 0)) || vps1_die "One or more snapshot downloads failed."

(
  cd "$staging_dir"
  zip -q "$archive_name" -- "${SELECTED[@]}"
)
mv "${staging_dir}/${archive_name}" "$archive_path"

echo
echo "✔ Download complete: ${archive_path}"
