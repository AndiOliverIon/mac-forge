#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/configs/web.json"

#######################################
# Load forge config
#######################################
# shellcheck disable=SC1091
source "$SCRIPT_DIR/forge.sh"

#######################################
# Helpers
#######################################
die() {
  echo "✖ $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

#######################################
# Requirements
#######################################
require_cmd jq
require_cmd fzf
require_cmd osascript

[[ -f "$CONFIG_FILE" ]] || die "Missing config file: $CONFIG_FILE"

#######################################
# Pick entry
#######################################
selection="$(
  jq -r '.[] | select(.name and .url) | "\(.name)\t\(.url)"' "$CONFIG_FILE" |
    fzf --prompt="web > " --with-nth=1 --delimiter=$'\t'
)" || exit 0

name="${selection%%$'\t'*}"
url="${selection#*$'\t'}"

[[ -n "${url:-}" ]] || die "No url selected."

#######################################
# Get optional space (first match only)
#######################################
space="$(
  jq -r --arg n "$name" '
    [.[] | select(.name==$n) | (.space // empty)]
    | first // empty
  ' "$CONFIG_FILE"
)"

echo "Opening in Arc${space:+ on space $space}: $url"

#######################################
# Open in Arc
#######################################
# Use argv passing so quotes/spaces don't break AppleScript
if ! osascript - "$url" "$space" <<'APPLESCRIPT'
on run argv
  set theURL to item 1 of argv
  set theSpace to ""
  if (count of argv) ≥ 2 then set theSpace to item 2 of argv

  tell application "Arc"
    activate
    if (count of windows) = 0 then
      try
        make new window
      end try
    end if

    if (count of windows) = 0 then error "No Arc window available"

    if theSpace is not "" then
      try
        tell front window
          tell space theSpace
            make new tab with properties {URL:theURL}
            focus
          end tell
        end tell
        return
      on error
        -- fallthrough to default tab open
      end try
    end if

    tell front window
      make new tab with properties {URL:theURL}
    end tell
  end tell
end run
APPLESCRIPT
then
  # Fallback if AppleScript fails (Arc scripting changed, space missing, etc.)
  open -a "Arc" "$url"
fi

echo "Opened: $name"
