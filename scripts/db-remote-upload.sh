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
  open "$SMB_URL"
  
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
    die "Failed to mount $MOUNT_PATH."
  fi
fi

#######################################
# Step 1 — Pick Local Source Category
#######################################
: "${FORGE_WORK_STATE_FILE:?FORGE_WORK_STATE_FILE must be set by forge.sh}"
source_tsv="$(
  jq -r '
    ."download-destinations" // []
    | .[]
    | select(.title != null and .path != null)
    | [.title, .path] | @tsv
  ' "$FORGE_WORK_STATE_FILE"
)"

[[ -n "${source_tsv//$'\n'/}" ]] || die "No local source categories found in: $FORGE_WORK_STATE_FILE"

chosen_source_line="$(
  printf '%s\n' "$source_tsv" \
    | fzf --prompt='Local Source Category > ' --delimiter=$'\t' --with-nth=1,2 --height=40%
)" || die "No source category selected."

source_title="$(printf '%s' "$chosen_source_line" | cut -f1)"
source_path_raw="$(printf '%s' "$chosen_source_line" | cut -f2-)"

# Expand ~ in source path
eval source_path="$source_path_raw"

[[ -d "$source_path" ]] || die "Source path does not exist: $source_path"

#######################################
# Step 2 — Pick Local Backup (.bak)
#######################################
echo "🔍 Scanning backups in [$source_title] $source_path..."

mapfile -t BACKUP_LIST < <(
  find "$source_path" -maxdepth 1 -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print0 | 
  xargs -0 ls -t |
  sed "s|^$source_path/||"
)

((${#BACKUP_LIST[@]} > 0)) || die "No .bak files found in $source_path."

SELECTED_FILE="$(
  printf '%s\n' "${BACKUP_LIST[@]}" | fzf --prompt="Select file to upload > " --height=60% --reverse
)" || die "No file selected."

SOURCE_FULL="$source_path/$SELECTED_FILE"

#######################################
# Step 3 — Pick Remote Destination Folder
#######################################
echo "🔍 Scanning destination folders on $MOUNT_PATH..."

# List root + first level directories
mapfile -t DEST_FOLDERS < <(
  echo "."
  find "$MOUNT_PATH" -maxdepth 1 -type d ! -path "$MOUNT_PATH" -exec basename {} \;
)

SELECTED_DEST_DIR="$(
  printf '%s\n' "${DEST_FOLDERS[@]}" | fzf --prompt="Select destination folder on share > " --height=40%
)" || die "No destination folder selected."

if [[ "$SELECTED_DEST_DIR" == "." ]]; then
  DEST_FULL_PATH="$MOUNT_PATH"
else
  DEST_FULL_PATH="$MOUNT_PATH/$SELECTED_DEST_DIR"
fi

#######################################
# Step 4 — Transfer with progress
#######################################
TARGET_FULL="${DEST_FULL_PATH}/$SELECTED_FILE"

echo
echo "🚀 Uploading Backup"
echo "   Source      : $SOURCE_FULL"
echo "   Destination : $TARGET_FULL"
echo

rsync -ah --progress "$SOURCE_FULL" "$DEST_FULL_PATH/"

echo
echo "✔ Upload complete: $TARGET_FULL"
