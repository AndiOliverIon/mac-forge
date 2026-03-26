#!/opt/homebrew/bin/bash
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

# Configuration
MOUNT_PATH="/Volumes/shared-files"
SMB_URL="smb://portainer.ardis.eu/shared-files"

# Pre-check: Is it mounted? If not, try to mount it.
if [[ ! -d "$MOUNT_PATH" ]]; then
  echo "📡 Mount not found. Attempting to connect to $SMB_URL..."
  
  # On macOS, 'open' is the cleanest way to trigger a mount with keychain credentials
  open "$SMB_URL"
  
  # Wait up to 10 seconds for the mount to appear
  echo -n "⏳ Waiting for mount..."
  for i in {1..10}; do
    if [[ -d "$MOUNT_PATH" ]]; then
      echo " OK!"
      break
    fi
    echo -n "."
    sleep 1
  done

  if [[ ! -d "$MOUNT_PATH" ]]; then
    echo
    die "Failed to mount $MOUNT_PATH. Please check your connection or connect manually in Finder once."
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

SELECTED_REL="$(
  printf '%s\n' "${BACKUP_LIST[@]}" | fzf --prompt="Select backup from share > " --height=70% --reverse
)" || die "No backup selected."

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
