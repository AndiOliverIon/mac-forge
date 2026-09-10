#!/usr/bin/env bash
set -euo pipefail

#######################################
# show - pick an informational section via fzf (or pass its id) and print
#         its output in the terminal. Sections are data-driven from
#         configs/show-info.json; add entries there to extend 'show'
#         without changing this script.
#######################################

die() {
  echo "✖ $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd jq
require_cmd fzf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="${FORGE_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
SECTIONS_CONFIG="${FORGE_SHOW_CONFIG:-$FORGE_ROOT/configs/show-info.json}"

[[ -f "$SECTIONS_CONFIG" ]] || die "Sections config not found at $SECTIONS_CONFIG"

jq -e '.sections | type == "array"' "$SECTIONS_CONFIG" >/dev/null 2>&1 \
  || die "Invalid sections config: $SECTIONS_CONFIG"

selected_id="${1:-}"

if [[ -z "$selected_id" ]]; then
  selected_id="$(
    jq -r '.sections[] | [.id, .label, .description] | @tsv' "$SECTIONS_CONFIG" \
      | fzf --prompt='show > ' --delimiter=$'\t' --with-nth=2,3 --height=40% --reverse \
      | cut -f1
  )"
  [[ -n "$selected_id" ]] || die "No section selected."
fi

command_str="$(
  jq -r --arg id "$selected_id" \
    '.sections[] | select(.id == $id) | .command // empty' "$SECTIONS_CONFIG"
)"

[[ -n "$command_str" ]] || die "Unknown show section '$selected_id'."

bash -c "$command_str"
