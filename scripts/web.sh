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

# Default browser from forge if not set
BROWSER="${FORGE_BROWSER:-Brave Browser}"
PLATFORM="$(uname -s)"

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

case "$PLATFORM" in
  Darwin)
    require_cmd osascript
    require_cmd open
    ;;
  Linux)
    require_cmd xdg-open
    ;;
  *)
    die "Unsupported platform: $PLATFORM"
    ;;
esac

[[ -f "$CONFIG_FILE" ]] || die "Missing config file: $CONFIG_FILE"

#######################################
# Handle parameters
#######################################
ACTION="${1:-go}"

if [[ "$ACTION" == "change" ]]; then
  # Settle a default browser
  echo "Select a default browser for 'web' command:"
  if [[ "$PLATFORM" == "Darwin" ]]; then
    browser_choices=$'Brave Browser\nGoogle Chrome\nSafari\nFirefox\nMicrosoft Edge'
  else
    browser_choices=$'Default browser\nBrave Browser\nGoogle Chrome\nFirefox\nChromium\nMicrosoft Edge'
  fi
  selected_browser=$(printf '%s\n' "$browser_choices" | fzf --prompt="browser > ")
  
  if [[ -n "$selected_browser" ]]; then
    python3 - "$FORGE_WORK_STATE_FILE" "$selected_browser" <<'PY'
import json, sys
path, browser = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    j = json.load(f)
j["browser"] = browser
with open(path, "w", encoding="utf-8") as f:
    json.dump(j, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    echo "✓ Default browser set to: $selected_browser"
    exit 0
  fi
  exit 0
fi

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

echo "Opening in $BROWSER${space:+ on space $space}: $url"

#######################################
# Open in Browser
#######################################
if [[ "$PLATFORM" == "Linux" ]]; then
  case "$BROWSER" in
    "Google Chrome")
      browser_command="google-chrome"
      ;;
    "Firefox")
      browser_command="firefox"
      ;;
    "Chromium")
      browser_command="chromium"
      ;;
    "Brave Browser")
      browser_command="brave-browser"
      ;;
    "Microsoft Edge")
      browser_command="microsoft-edge"
      ;;
    *)
      browser_command="xdg-open"
      ;;
  esac

  if ! command -v "$browser_command" >/dev/null 2>&1; then
    echo "Browser '$BROWSER' is unavailable; using the system default."
    browser_command="xdg-open"
  fi

  "$browser_command" "$url" >/dev/null 2>&1 &
else
  # Generic browser open
  open -a "$BROWSER" "$url"
fi

echo "Opened: $name"
