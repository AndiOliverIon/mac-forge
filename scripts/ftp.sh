#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${FORGE_CONFIG_LOCAL_DIR:-$PROJECT_ROOT/config-local}/local-store.json"
PANEL="$SCRIPT_DIR/ftp-panel.py"

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
require_cmd python3

[[ -f "$CONFIG_FILE" ]] || die "Missing config file: $CONFIG_FILE"
[[ -f "$PANEL" ]] || die "Missing panel script: $PANEL"

count="$(jq '(.["ftp-connections"] // []) | length' "$CONFIG_FILE")"
[[ "$count" -gt 0 ]] || die "No ftp-connections found in $CONFIG_FILE"

#######################################
# Pick a connection by display
#######################################
selection="$(
  jq -r '.["ftp-connections"][] | select(.display) | .display' "$CONFIG_FILE" |
    fzf --prompt="ftp > " --height=40% --reverse
)" || exit 0

[[ -n "${selection:-}" ]] || exit 0

#######################################
# Load connection detail
#######################################
read -r host port user <<EOF
$(jq -r --arg d "$selection" '
  .["ftp-connections"][] | select(.display == $d) |
  "\(.host)\t\(.port // 21)\t\(.user)"' "$CONFIG_FILE" | head -1 | tr '\t' ' ')
EOF

[[ -n "${host:-}" ]] || die "Connection '$selection' has no host."

FTP_PASSWORD="$(jq -r --arg d "$selection" '
  .["ftp-connections"][] | select(.display == $d) | (.password // "")' "$CONFIG_FILE")"
export FTP_PASSWORD

#######################################
# Launch dual-pane browser
#######################################
python3 "$PANEL" "$host" "$port" "$user" "$selection"
status=$?
unset FTP_PASSWORD
exit "$status"
