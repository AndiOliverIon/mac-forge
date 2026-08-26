#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_STATIONS_FILE="${FORGE_LOCAL_STATIONS_FILE:-$PROJECT_ROOT/config-local/stations.json}"

[[ -r "$LOCAL_STATIONS_FILE" ]] || {
  echo "ERROR: Missing local station facts: $LOCAL_STATIONS_FILE" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required." >&2
  exit 1
}

mac_address="$(jq -er '.stations.masterchief.identifiers.macAddresses[0]' "$LOCAL_STATIONS_FILE")"
wifi_subnet="$(jq -er '.stations.masterchief.network.wifi.subnet' "$LOCAL_STATIONS_FILE")"
broadcast_address="$(python3 - "$wifi_subnet" <<'PY'
import ipaddress
import sys

print(ipaddress.ip_network(sys.argv[1], strict=False).broadcast_address)
PY
)"

echo "Attempting to wake MasterChief from sleep..."
wakeonlan -i "$broadcast_address" "$mac_address"
