#!/opt/homebrew/bin/bash
# vps1-db-upload.sh — upload a local .bak into the dedicated vps1 snapshots
# folder, so it can then be restored with v1r.
#
# Usage: vps1-db-upload.sh [source-file-or-dir]
#        - no arg      : if the current directory has any .bak, pick from there;
#                        otherwise fall back to ~/sql/snapshots (or VPS1_UPLOAD_DIR)
#        - a directory : pick a .bak from that directory
#        - a .bak file : upload that file directly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd ssh
vps1_require_cmd rsync

#######################################
# Resolve source .bak
#######################################
list_baks_in_dir() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -iname '*.bak' ! -name '._*' -print 2>/dev/null \
    | sort \
    | sed "s|^$dir/||"
}

if [[ $# -ge 1 ]]; then
  # Explicit source provided: a .bak file or a directory.
  SRC="$1"
  if [[ -f "$SRC" ]]; then
    selected_path="$SRC"
  else
    [[ -d "$SRC" ]] || vps1_die "Source path not found: $SRC"
  fi
else
  # No arg: prefer the current directory if it has any .bak, else fall back.
  if [[ -n "$(list_baks_in_dir "$PWD")" ]]; then
    SRC="$PWD"
    echo "Found .bak file(s) in current directory: $PWD"
  else
    SRC="${VPS1_UPLOAD_DIR:-$HOME/sql/snapshots}"
    echo "No .bak in current directory; using fallback: $SRC"
  fi
fi

# If we don't yet have a concrete file, pick one from the resolved directory.
if [[ -z "${selected_path:-}" ]]; then
  [[ -d "$SRC" ]] || vps1_die "Source directory not found: $SRC"
  vps1_require_cmd fzf

  mapfile -t BAKS < <(list_baks_in_dir "$SRC")
  ((${#BAKS[@]} > 0)) || vps1_die "No .bak files found in: $SRC"

  selected="$(printf '%s\n' "${BAKS[@]}" | fzf --prompt='Select local .bak to upload > ' --height=60% --reverse)" \
    || vps1_die "No file selected."
  selected_path="$SRC/$selected"
fi

[[ -f "$selected_path" ]] || vps1_die "Selected file not found: $selected_path"
name="$(basename "$selected_path")"

#######################################
# Transfer
#######################################
echo
echo "🚀 Uploading local snapshot to vps1"
echo "   Source      : $selected_path"
echo "   Destination : ${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/${name}"
echo

rsync -ah --progress \
  -e "ssh -o ConnectTimeout=$VPS1_SSH_CONNECT_TIMEOUT" \
  "$selected_path" \
  "${VPS1_SSH_HOST}:${VPS1_SNAPSHOTS_HOST_DIR}/"

# Ensure SQL Server (container mssql uid) can read the uploaded file.
vps1_chmod_snapshot "$name"

vps1_ssh "test -f '$VPS1_SNAPSHOTS_HOST_DIR/$name'" \
  || vps1_die "Upload reported success but file not found on vps1: $VPS1_SNAPSHOTS_HOST_DIR/$name"

echo
echo "✔ Upload complete: ${VPS1_SNAPSHOTS_HOST_DIR}/${name}"
echo "  Restore it on vps1 with:  v1r"
