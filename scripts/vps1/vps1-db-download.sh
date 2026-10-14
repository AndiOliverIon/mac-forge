#!/usr/bin/env bash
# vps1-db-download.sh — download .bak files from the dedicated vps1 snapshots
# folder to the current directory. Multiple selections are downloaded concurrently
# and packaged as snapshot-YYYY-MM-DD-HHMMSS.zip.
#
# Usage: vps1-db-download.sh [--d]
#   --d  After every selected file downloads successfully, delete those snapshots
#        from vps1. A partial download deletes nothing. Type 'delete' to confirm.
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
DELETE_AFTER=0
if [[ $# -gt 0 ]]; then
  [[ $# -eq 1 && "$1" == "--d" ]] || vps1_die "Usage: $(basename "$0") [--d]"
  DELETE_AFTER=1
fi
DEST_DIR="$PWD"
[[ -d "$DEST_DIR" && -w "$DEST_DIR" ]] || vps1_die "Destination not writable: $DEST_DIR"

snapshot_name_is_safe() {
  local name="$1"
  [[ "$name" == *.bak ]] || return 1
  [[ "$name" != */* && "$name" != *..* && "$name" != *"'"* ]] || return 1
  [[ "$name" != *$'\n'* && "$name" != *$'\r'* ]] || return 1
}

snapshot_was_listed() {
  local name="$1" candidate
  for candidate in "${BAKS[@]}"; do
    if [[ "$candidate" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

local_file_bytes() {
  local path="$1" bytes
  if bytes="$(stat -c %s "$path" 2>/dev/null)"; then
    printf '%s\n' "$bytes"
    return 0
  fi
  stat -f %z "$path"
}

delete_downloaded_snapshots() {
  local local_dir="$1" name local_bytes remote_bytes answer deleted=0
  shift
  ((DELETE_AFTER)) || return 0

  [[ -t 0 ]] || vps1_die "Refusing to delete vps1 snapshots without an interactive terminal. Download kept; nothing was deleted on vps1."

  for name in "$@"; do
    snapshot_name_is_safe "$name" || vps1_die "Refusing unexpected snapshot name: $name"
    snapshot_was_listed "$name" || vps1_die "Refusing snapshot that was not listed: $name"
    [[ -f "$local_dir/$name" && -s "$local_dir/$name" ]] \
      || vps1_die "Refusing to delete [$name]; local copy is missing or empty. Download kept; nothing was deleted on vps1."
    local_bytes="$(local_file_bytes "$local_dir/$name")"
    remote_bytes="$(vps1_ssh "stat -c %s '$VPS1_SNAPSHOTS_HOST_DIR/$name'")" \
      || vps1_die "Refusing to delete [$name]; could not read its size on vps1. Download kept; nothing was deleted on vps1."
    remote_bytes="${remote_bytes//[[:space:]]/}"
    [[ -n "$local_bytes" && "$local_bytes" == "$remote_bytes" ]] \
      || vps1_die "Refusing to delete [$name]; local copy does not match the vps1 snapshot. Download kept; nothing was deleted on vps1."
  done

  echo
  echo "⚠ Download succeeded. About to PERMANENTLY DELETE these snapshot file(s) on vps1:"
  for name in "$@"; do
    echo "    $VPS1_SNAPSHOTS_HOST_DIR/$name"
  done
  echo "  Host: $VPS1_SSH_HOST"
  echo
  echo "Type 'delete' to confirm."
  read -r -p "> " answer
  [[ "$answer" == "delete" ]] || vps1_die "Confirmation mismatch. Download kept; nothing was deleted on vps1."

  for name in "$@"; do
    vps1_log_step "Deleting snapshot [$name] on vps1..."
    vps1_ssh "test -f '$VPS1_SNAPSHOTS_HOST_DIR/$name'" \
      || vps1_die "Snapshot not found on vps1: $VPS1_SNAPSHOTS_HOST_DIR/$name. $deleted snapshot(s) were already deleted."
    vps1_ssh "docker exec -u 0 '$VPS1_SQL_CONTAINER' rm -f -- '$VPS1_SNAPSHOTS_CONTAINER_DIR/$name'" \
      || vps1_die "Failed to delete [$name] on vps1. $deleted snapshot(s) were already deleted."
    vps1_ssh "test ! -e '$VPS1_SNAPSHOTS_HOST_DIR/$name'" \
      || vps1_die "Snapshot still exists on vps1: $VPS1_SNAPSHOTS_HOST_DIR/$name. $deleted snapshot(s) were already deleted."
    deleted=$((deleted + 1))
  done

  echo "✔ Deleted $# snapshot(s) on vps1."
}

#######################################
# Pick a .bak from the vps1 snapshots folder
#######################################
mapfile -t BAKS < <(vps1_list_snapshots)
((${#BAKS[@]} > 0)) || vps1_die "No .bak files in vps1 snapshots dir: $VPS1_SNAPSHOTS_HOST_DIR"

selected="$(printf '%s\n' "${BAKS[@]}" | fzf --multi --prompt='Select vps1 .bak file(s) to download (Tab selects) > ' --height=60% --reverse)" \
  || vps1_die "No file selected."
[[ -n "$selected" ]] || vps1_die "No file selected."
mapfile -t SELECTED <<< "$selected"

if ((DELETE_AFTER)); then
  for selected in "${SELECTED[@]}"; do
    snapshot_name_is_safe "$selected" \
      || vps1_die "Refusing to download for deletion; unexpected snapshot name: $selected"
    snapshot_was_listed "$selected" \
      || vps1_die "Refusing to download for deletion; snapshot was not listed: $selected"
  done
fi

#######################################
# Transfer
#######################################
if ((${#SELECTED[@]} == 1)); then
  selected="${SELECTED[0]}"

  echo
  echo "🚀 Downloading vps1 snapshot"
  echo "   Source      : ${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${selected}"
  echo "   Destination : ${DEST_DIR}/${selected}"
  if ((DELETE_AFTER)); then
    echo "   After success : delete this snapshot from vps1"
  fi
  echo

  rsync -ah --progress \
    -e "ssh -o ConnectTimeout=$VPS1_SSH_CONNECT_TIMEOUT" \
    "${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${selected}" \
    "${DEST_DIR}/"

  echo
  echo "✔ Download complete: ${DEST_DIR}/${selected}"
  delete_downloaded_snapshots "$DEST_DIR" "$selected"
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
if ((DELETE_AFTER)); then
  echo "   After success : delete these snapshots from vps1"
fi
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
delete_downloaded_snapshots "$staging_dir" "${SELECTED[@]}"
