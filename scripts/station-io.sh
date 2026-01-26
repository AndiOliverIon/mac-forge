#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config (same logic as your scripts)
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
else
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Helpers
#######################################
die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

usage() {
  cat <<'EOF'
Usage:
  cross-station.sh [--move]

Behavior:
  1) Shows files + folders under the current directory via fzf.
  2) Then shows "station-destinations" from your forge *state* json via fzf (title + path).
  3) Copies (default) or moves (--move) the selected item into the chosen destination path.

Requirements:
  - forge.sh must set FORGE_WORK_STATE_FILE
  - jq, fzf, rsync
EOF
}

#######################################
# Args
#######################################
MODE="copy"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--move" ]]; then
  MODE="move"
  shift
fi
((${#@} == 0)) || die "Unknown arguments: $* (use --help)"

#######################################
# Preconditions
#######################################
require_cmd fzf
require_cmd jq
require_cmd rsync

#######################################
# Load state json file (same pattern you showed)
#######################################
: "${FORGE_WORK_STATE_FILE:?FORGE_WORK_STATE_FILE must be set by forge.sh}"
STATE_FILE="$FORGE_WORK_STATE_FILE"
[[ -f "$STATE_FILE" ]] || die "work-state.json not found at: $STATE_FILE"

#######################################
# Pick source (file/folder) under CWD
#######################################
CWD="$(pwd)"

#######################################
# List candidates: folders first, then files (alphabetical)
#######################################
list_candidates() {
  local root="$CWD"

  # Folders
  find "$root" \
    -mindepth 1 -maxdepth 1 \
    -type d \
    ! -name ".git" \
    -print 2>/dev/null |
    sed "s|^$root/||" |
    sort |
    awk '{ printf "📁 %s\n", $0 }'

  # Files
  find "$root" \
    -mindepth 1 -maxdepth 1 \
    -type f \
    ! -name ".DS_Store" \
    -print 2>/dev/null |
    sed "s|^$root/||" |
    sort |
    awk '{ printf "📄 %s\n", $0 }'
}

selected_rel="$(
  list_candidates | fzf --prompt="Select source (from $CWD) > " --height=80%
)" || die "No source selected."

# Remove icon prefix
selected_rel="${selected_rel#📁 }"
selected_rel="${selected_rel#📄 }"

if [[ "$selected_rel" == "." ]]; then
  selected_src="$CWD"
else
  selected_src="$CWD/$selected_rel"
fi
[[ -e "$selected_src" ]] || die "Selected source does not exist: $selected_src"

#######################################
# Pick destination from station-destinations
#######################################
dest_tsv="$(
  jq -r '
    .["station-destinations"] // []
    | .[]
    | select(.title != null and .path != null)
    | [.title, .path] | @tsv
  ' "$STATE_FILE"
)"

[[ -n "${dest_tsv//$'\n'/}" ]] || die "No station-destinations found in: $STATE_FILE"

selected_dest_line="$(
  printf '%s\n' "$dest_tsv" \
    | fzf --prompt="Select destination station > " --with-nth=1,2 --delimiter=$'\t' --height=60%
)" || die "No destination selected."

dest_title="$(printf '%s' "$selected_dest_line" | cut -f1)"
dest_path="$(printf '%s' "$selected_dest_line" | cut -f2-)"

[[ -n "$dest_path" ]] || die "Destination path is empty."
[[ -d "$dest_path" ]] || die "Destination path does not exist or is not a directory: $dest_path"

#######################################
# Execute copy/move into destination
#######################################
base_name="$(basename "$selected_src")"
target="$dest_path/$base_name"

echo "Source      : $selected_src"
echo "Destination : [$dest_title] $dest_path"
echo "Operation   : $MODE"
echo "Target      : $target"
echo

if [[ "$MODE" == "move" ]]; then
  # If target exists, overwrite by removing first (mv has tricky overwrite semantics for dirs)
  if [[ -e "$target" ]]; then
    rm -rf -- "$target"
  fi
  mv -- "$selected_src" "$dest_path/"
  echo "OK: moved -> $dest_path/"
else
  # Copy:
  # - files: rsync to exact target path
  # - dirs : rsync into dest_path (creates dest_path/base_name)
  if [[ -d "$selected_src" ]]; then
    if [[ -e "$target" ]]; then
      rm -rf -- "$target"
    fi
    rsync -a -- "$selected_src/" "$target/"
  else
    rsync -a -- "$selected_src" "$target"
  fi
  echo "OK: copied -> $target"
fi
