#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIONS_FILE="${FORGE_STATIONS_FILE:-$PROJECT_ROOT/configs/stations.json}"
LEGACY_STATE_FILE="${FORGE_WORK_STATE_FILE:-$PROJECT_ROOT/configs/work-state.json}"
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
if [[ ! -f "$STATIONS_FILE" && ! -f "$LEGACY_STATE_FILE" ]]; then
  die "Missing stations inventory: $STATIONS_FILE"
fi

#######################################
# Pick a station
#######################################
# Prefer the canonical stations inventory. The work-state fallback remains only
# for checkouts that have not migrated yet.
inventory_file="$STATIONS_FILE"
[[ -f "$inventory_file" ]] || inventory_file="$LEGACY_STATE_FILE"

if [[ -n "${1:-}" ]]; then
  station="$1"
else
  station="$(
    python3 -c "
import json, sys
with open('$inventory_file') as f:
    data = json.load(f)
for s in data.get('stations', []):
    station_id = s.get('id') or s.get('name')
    name = s.get('name') or station_id
    primary_alias = s.get('access', {}).get('ssh', {}).get('primaryAlias')
    if station_id and primary_alias:
        print(f'{station_id}\t{name}')
" | fzf --prompt="sshc > " --height=40% --reverse
  )" || exit 0
  station="${station%%$'\t'*}"
fi

[[ -n "${station:-}" ]] || exit 0

station_resolution="$(
  python3 - "$inventory_file" "$station" <<'PY'
import json
import sys

inventory_path, requested = sys.argv[1:]
requested_folded = requested.casefold()

with open(inventory_path) as inventory_stream:
    stations = json.load(inventory_stream).get("stations", [])

for item in stations:
    station_id = item.get("id") or item.get("name", "")
    name = item.get("name") or station_id
    ssh = item.get("access", {}).get("ssh", {})
    aliases = ssh.get("aliases", [])
    candidates = [station_id, name, *aliases]
    if any(str(candidate).casefold() == requested_folded for candidate in candidates):
        print(ssh.get("primaryAlias", ""))
        print(name)
        break
else:
    print(requested)
    print(requested)
PY
)"

host="${station_resolution%%$'\n'*}"
station="${station_resolution#*$'\n'}"
[[ -n "$host" ]] || die "$station has no SSH endpoint in the stations inventory."

#######################################
# Launch dual-pane SSH/SFTP browser
#######################################
exec python3 "$PANEL" "$host" "$station"
