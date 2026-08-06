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
require_cmd rsync
require_cmd stat

# Configuration
case "$(uname -s)" in
  Darwin)
    MOUNT_PATH="${RDOWN_MOUNT_PATH:-/Volumes/shared-files}"
    SMB_URL="${RDOWN_SMB_URL:-smb://portainer.ardis.eu/shared-files}"
    ;;
  Linux)
    MOUNT_PATH="${RDOWN_MOUNT_PATH:-/mnt/shared-files}"
    SMB_URL="${RDOWN_SMB_URL:-//portainer.ardis.eu/shared-files}"
    ;;
  *)
    die "Unsupported operating system: $(uname -s)"
    ;;
esac
MOUNT_WAIT_SECONDS="${RDOWN_MOUNT_WAIT_SECONDS:-120}"
MOUNT_RECHECK_SECONDS="${RDOWN_MOUNT_RECHECK_SECONDS:-2}"

[[ "$MOUNT_WAIT_SECONDS" =~ ^[0-9]+$ && "$MOUNT_WAIT_SECONDS" -gt 0 ]] || die "RDOWN_MOUNT_WAIT_SECONDS must be a positive integer."
[[ "$MOUNT_RECHECK_SECONDS" =~ ^[0-9]+$ && "$MOUNT_RECHECK_SECONDS" -gt 0 ]] || die "RDOWN_MOUNT_RECHECK_SECONDS must be a positive integer."

file_size_bytes() {
  stat -f '%z' -- "$1"
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

is_mount_ready() {
  [[ -d "$MOUNT_PATH" ]] || return 1
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$MOUNT_PATH"
  else
    mount | grep -F " on $MOUNT_PATH " >/dev/null 2>&1
  fi
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

# Pre-check: Is it mounted? On macOS, try to mount it through Finder.
if ! is_mount_ready; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "📡 Mount not found. Attempting to connect to $SMB_URL..."
    open "$SMB_URL"
    wait_for_mount || die "Failed to mount $MOUNT_PATH. Please check your connection or connect manually in Finder once."
  else
    die "SMB share is not mounted at $MOUNT_PATH. Mount $SMB_URL there or set RDOWN_MOUNT_PATH."
  fi
fi

#######################################
# Step 1 — Pick Backup from SMB Mount
#######################################
echo "🔍 Scanning backups on $MOUNT_PATH..."

# Search for .bak files (case-insensitive) under the mount
# We use -maxdepth 2 to see the root and common subfolders (like per-server folders)
# Sort by modification time (newest first)
mapfile -t BACKUP_LIST < <(
  find "$MOUNT_PATH" -maxdepth 2 -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print0 | 
  xargs -0 ls -t |
  sed "s|^$MOUNT_PATH/||"
)

((${#BACKUP_LIST[@]} > 0)) || die "No .bak files found on the share."

BACKUP_ROWS=()
for backup_rel in "${BACKUP_LIST[@]}"; do
  backup_full="$MOUNT_PATH/$backup_rel"
  [[ -f "$backup_full" ]] || continue
  size_bytes="$(file_size_bytes "$backup_full")" || continue
  printf -v backup_row '[%9s]  %s\t%s' "$(human_file_size "$size_bytes")" "$backup_rel" "$backup_rel"
  BACKUP_ROWS+=("$backup_row")
done

((${#BACKUP_ROWS[@]} > 0)) || die "No readable .bak files found on the share."

SELECTED_ROW="$(
  printf '%s\n' "${BACKUP_ROWS[@]}" |
    fzf --prompt="Select backup from share > " --delimiter=$'\t' --with-nth=1 --height=70% --reverse
)" || die "No backup selected."
[[ "$SELECTED_ROW" == *$'\t'* ]] || die "Unexpected backup selection."
SELECTED_REL="${SELECTED_ROW#*$'\t'}"

SOURCE_FULL="$MOUNT_PATH/$SELECTED_REL"

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

# Expand ~ in destination path
eval dest_path="$dest_path_raw"

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
