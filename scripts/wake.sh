#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIONS_FILE="${FORGE_STATIONS_FILE:-$PROJECT_ROOT/configs/stations.json}"
LOCAL_STATIONS_FILE="${FORGE_LOCAL_STATIONS_FILE:-$PROJECT_ROOT/config-local/stations.json}"

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
require_cmd wakeonlan

[[ -f "$STATIONS_FILE" ]] || die "Missing stations inventory: $STATIONS_FILE"
[[ -r "$LOCAL_STATIONS_FILE" ]] || die "Missing local station facts: $LOCAL_STATIONS_FILE"

#######################################
# Pick a station (all stations, or pass a name)
#######################################
if [[ -n "${1:-}" ]]; then
  station="$1"
else
  station="$(
    python3 -c "
import json
with open('$STATIONS_FILE') as f:
    data = json.load(f)
for s in data.get('stations', []):
    station_id = s.get('id') or s.get('name')
    name = s.get('name') or station_id
    if station_id:
        print(f'{station_id}\t{name}')
" | fzf --prompt="wake > " --height=40% --reverse
  )" || exit 0
  station="${station%%$'\t'*}"
fi

[[ -n "${station:-}" ]] || exit 0

#######################################
# Resolve MAC address + directed broadcast from the inventory + local overlay.
# Emits: <name>\t<mac>\t<broadcast-or-empty>
# Exits non-zero with a specific message when the MAC is not configured, so the
# operator knows exactly which station facts to enrich.
#######################################
if ! resolution="$(
  python3 - "$STATIONS_FILE" "$LOCAL_STATIONS_FILE" "$station" <<'PY'
import ipaddress
import json
import sys

tracked_path, local_path, requested = sys.argv[1:]
requested_folded = requested.casefold()

with open(tracked_path) as tracked_stream:
    tracked = json.load(tracked_stream)
with open(local_path) as local_stream:
    local = json.load(local_stream)


def get_by_dotted(root, dotted_key):
    current = root
    for part in dotted_key.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


station = None
for item in tracked.get("stations", []):
    station_id = item.get("id") or item.get("name", "")
    name = item.get("name") or station_id
    aliases = item.get("access", {}).get("ssh", {}).get("aliases", [])
    candidates = [station_id, name, *aliases]
    if any(str(candidate).casefold() == requested_folded for candidate in candidates):
        station = item
        break

if station is None:
    sys.stderr.write(f"Unknown station: {requested}\n")
    sys.exit(2)

station_id = station.get("id") or station.get("name", "")
name = station.get("name") or station_id
endpoints = station.get("network", {}).get("endpoints", [])

# MAC lookup key: prefer access.wake, then any endpoint that declares one.
mac_key = station.get("access", {}).get("wake", {}).get("macAddressLocalFactsKey")
if not mac_key:
    for endpoint in endpoints:
        if endpoint.get("macAddressLocalFactsKey"):
            mac_key = endpoint["macAddressLocalFactsKey"]
            break

mac = None
if mac_key:
    value = get_by_dotted(local, mac_key)
    if isinstance(value, list):
        mac = value[0] if value else None
    elif isinstance(value, str):
        mac = value

if not mac:
    sys.stderr.write(
        f"{name} has no MAC address configured for Wake-on-LAN.\n"
        f"Enrich your station facts:\n"
        f"  1. configs/stations.json -> station '{station_id}': add "
        f"\"macAddressLocalFactsKey\" (on its wake block or a network endpoint)\n"
        f"  2. config-local/stations.json -> that key, e.g. "
        f"stations.{station_id}.identifiers.macAddresses\n"
    )
    sys.exit(3)

# Directed broadcast: prefer a wakeOnLan endpoint, else the default route.
chosen = None
for endpoint in endpoints:
    if endpoint.get("wakeOnLan"):
        chosen = endpoint
        break
if chosen is None:
    for endpoint in endpoints:
        if endpoint.get("defaultRoute"):
            chosen = endpoint
            break

broadcast = ""
if chosen and chosen.get("localFactsKey"):
    facts = get_by_dotted(local, chosen["localFactsKey"])
    if isinstance(facts, dict) and facts.get("subnet"):
        try:
            broadcast = str(
                ipaddress.ip_network(facts["subnet"], strict=False).broadcast_address
            )
        except ValueError:
            broadcast = ""

print(f"{name}\t{mac}\t{broadcast}")
PY
)"; then
  exit 1
fi

name="${resolution%%$'\t'*}"
rest="${resolution#*$'\t'}"
mac="${rest%%$'\t'*}"
broadcast="${rest#*$'\t'}"

#######################################
# Send the magic packet
#######################################
echo "Sending Wake-on-LAN to $name ($mac)..."
if [[ -n "$broadcast" ]]; then
  wakeonlan -i "$broadcast" "$mac"
else
  wakeonlan "$mac"
fi
