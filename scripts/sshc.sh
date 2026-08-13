#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${FORGE_WORK_STATE_FILE:-$PROJECT_ROOT/configs/work-state.json}"
PANEL="$SCRIPT_DIR/sftp-panel.py"

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
require_cmd fzf
require_cmd python3
python3 -c "import paramiko" 2>/dev/null || die "Python module 'paramiko' not found. Install with: python3 -m pip install --user paramiko"

[[ -f "$PANEL" ]] || die "Missing panel script: $PANEL"
[[ -f "$STATE_FILE" ]] || die "Missing state file: $STATE_FILE"

#######################################
# Pick a station
#######################################
# Station name may be passed directly (e.g. sshc masterchief); otherwise fzf-pick
# from the stations inventory in work-state.json.
if [[ -n "${1:-}" ]]; then
  station="$1"
else
  station="$(
    python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    data = json.load(f)
for s in data.get('stations', []):
    n = s.get('name')
    if n:
        print(n)
" | fzf --prompt="sshc > " --height=40% --reverse
  )" || exit 0
fi

[[ -n "${station:-}" ]] || exit 0

# ssh hosts are lowercase; work-state uses capitalized display names.
host="$(printf '%s' "$station" | tr '[:upper:]' '[:lower:]')"

#######################################
# Launch dual-pane SSH/SFTP browser
#######################################
exec python3 "$PANEL" "$host" "$station"
