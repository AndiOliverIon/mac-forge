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
# Standard interval (seconds) between magic packets when cycling.
# Hardcoded on purpose: there is intentionally no CLI flag for this yet.
#######################################
PACKET_INTERVAL_SECONDS=2

#######################################
# Parse arguments: optional station name + --cycle N
#   wake                       -> pick a station, send 1 packet per card
#   wake masterchief           -> send 1 packet per card
#   wake masterchief --cycle 3 -> send 3 packets per card
#######################################
cycle=1
station=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycle)
      shift
      [[ $# -gt 0 ]] || die "--cycle requires a count."
      cycle="$1"
      ;;
    --cycle=*)
      cycle="${1#*=}"
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$station" ]] || die "Unexpected argument: $1"
      station="$1"
      ;;
  esac
  shift
done

[[ "$cycle" =~ ^[0-9]+$ && "$cycle" -ge 1 ]] || die "--cycle must be a positive integer."

#######################################
# Pick a station when one was not passed
#######################################
if [[ -z "$station" ]]; then
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
# Resolve every card (network endpoint that declares a MAC) plus its directed
# broadcast from the inventory + local overlay.
# Emits: first line = <station-name>; then one line per card:
#   <card-label>\t<mac>\t<broadcast-or-empty>
# Exits non-zero with a specific message when no MAC is configured, so the
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


def resolve_mac(key):
    value = get_by_dotted(local, key) if key else None
    if isinstance(value, list):
        return value[0] if value else None
    if isinstance(value, str):
        return value
    return None


def broadcast_from_localfacts(key):
    facts = get_by_dotted(local, key) if key else None
    if isinstance(facts, dict) and facts.get("subnet"):
        try:
            return str(
                ipaddress.ip_network(facts["subnet"], strict=False).broadcast_address
            )
        except ValueError:
            return ""
    return ""


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

cards = []
seen = set()

# One card per network endpoint that declares a MAC, each on its own broadcast.
for endpoint in endpoints:
    mac = resolve_mac(endpoint.get("macAddressLocalFactsKey"))
    if not mac or mac.casefold() in seen:
        continue
    seen.add(mac.casefold())
    label = endpoint.get("name") or endpoint.get("connectionType") or "card"
    broadcast = broadcast_from_localfacts(endpoint.get("localFactsKey"))
    cards.append((label, mac, broadcast))

# Fallback: stations that only declare a wake MAC (no per-endpoint MAC).
if not cards:
    mac = resolve_mac(
        station.get("access", {}).get("wake", {}).get("macAddressLocalFactsKey")
    )
    if mac:
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
        label = (chosen.get("name") if chosen else None) or "wake"
        broadcast = broadcast_from_localfacts(chosen.get("localFactsKey")) if chosen else ""
        cards.append((label, mac, broadcast))

if not cards:
    sys.stderr.write(
        f"{name} has no MAC address configured for Wake-on-LAN.\n"
        f"Enrich your station facts:\n"
        f"  1. configs/stations.json -> station '{station_id}': add "
        f"\"macAddressLocalFactsKey\" (on its wake block or a network endpoint)\n"
        f"  2. config-local/stations.json -> that key, e.g. "
        f"stations.{station_id}.identifiers.macAddresses.<type>.mac\n"
    )
    sys.exit(3)

print(name)
for label, mac, broadcast in cards:
    print(f"{label}\t{mac}\t{broadcast}")
PY
)"; then
  exit 1
fi

name="$(printf '%s\n' "$resolution" | head -n1)"
cards="$(printf '%s\n' "$resolution" | tail -n +2)"
card_count="$(printf '%s\n' "$cards" | grep -c . || true)"

#######################################
# Send the magic packet(s): every card, cycle times each, spaced by the
# standard interval. A single interval separates every packet uniformly.
#######################################
echo "Sending Wake-on-LAN to $name — ${card_count} card(s), cycle=${cycle} (interval ${PACKET_INTERVAL_SECONDS}s)..."

first=1
while IFS=$'\t' read -r label mac broadcast; do
  [[ -n "$mac" ]] || continue
  for ((i = 1; i <= cycle; i++)); do
    if [[ $first -eq 0 ]]; then
      sleep "$PACKET_INTERVAL_SECONDS"
    fi
    first=0
    if [[ -n "$broadcast" ]]; then
      echo "  [$label] packet $i/$cycle -> $mac via $broadcast"
      wakeonlan -i "$broadcast" "$mac"
    else
      echo "  [$label] packet $i/$cycle -> $mac"
      wakeonlan "$mac"
    fi
  done
done <<<"$cards"
