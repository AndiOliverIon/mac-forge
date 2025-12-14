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
require_cmd open

[[ -f "$CONFIG_FILE" ]] || die "Missing config file: $CONFIG_FILE"

#######################################
# Pick entry
#######################################
# Build a tab-separated list: name \t url
selection="$(
	jq -r '.[] | select(.name and .url) | "\(.name)\t\(.url)"' "$CONFIG_FILE" |
		fzf --prompt="web > " --with-nth=1 --delimiter=$'\t'
)" || exit 0

name="${selection%%$'\t'*}"
url="${selection#*$'\t'}"

[[ -n "${url:-}" ]] || die "No url selected."

#######################################
# Open in Arc
#######################################
# If Arc isn't installed under that name, macOS will error and you'll see it.
# if needed to be simple new window: open -a "Arc" "$url"
space="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .space // empty' "$CONFIG_FILE")"

echo "Opening in Arc on space $space: $url"

if [[ -n "${space:-}" ]]; then
	osascript <<APPLESCRIPT
tell application "Arc"
  tell front window
    tell space "$space"
      make new tab with properties {URL:"$url"}
    end tell
  end tell
  activate
end tell
APPLESCRIPT
else
	# No space specified: open in the *current* context (front window)
	osascript <<APPLESCRIPT
tell application "Arc"
  tell front window
    make new tab with properties {URL:"$url"}
  end tell
  activate
end tell
APPLESCRIPT
fi

echo "Opened: $name"
