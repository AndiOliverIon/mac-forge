#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

STATIONS_CONFIG="${FORGE_STATIONS_CONFIG:-$FORGE_ROOT/configs/stations.json}"
WINDOWS_TUNNEL_SCRIPT="${CERBER_HADES_TUNNEL_SCRIPT:-C:\mac-forge\windows\scripts\hades-tunnel.ps1}"
ANGULAR_URL="${CERBER_HADES_ANGULAR_URL:-http://localhost:4200}"

die() {
	echo "ERROR: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

usage() {
	cat <<'EOF'
Control the Hades development tunnel inside the Cerber Parallels guest.

Usage:
  cerber-hades-tunnel.sh up
  cerber-hades-tunnel.sh status
  cerber-hades-tunnel.sh down

Mac aliases:
  cerber-tunnel-up
  cerber-tunnel-status
  cerber-tunnel-down
EOF
}

read_cerber_vm_name() {
	python3 - "$STATIONS_CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as config_file:
    config = json.load(config_file)

for station in config.get("stations", []):
    if station.get("id") == "cerber":
        vm_name = station.get("identifiers", {}).get("vmName")
        if vm_name:
            print(vm_name)
            raise SystemExit(0)

raise SystemExit("Cerber VM name is missing from configs/stations.json.")
PY
}

require_cerber_running() {
	local vm_status

	vm_status="$(prlctl status "$VM_NAME" 2>&1)" || die "$vm_status"
	case "$vm_status" in
	*running*) ;;
	*) die "Cerber is not running: $vm_status" ;;
	esac
}

run_tunnel_action() {
	# Parallels current-user execution lets the hidden ssh.exe survive after this command returns.
	prlctl exec "$VM_NAME" --current-user powershell.exe -NoLogo -NoProfile \
		-File "$WINDOWS_TUNNEL_SCRIPT" -Action "$1"
}

verify_angular_on_hades() {
	curl --fail --silent --show-error --output /dev/null --max-time 5 "$ANGULAR_URL" ||
		die "Angular is not responding on Hades at $ANGULAR_URL. Start it before opening the Cerber tunnel."
}

verify_angular_from_cerber() {
	prlctl exec "$VM_NAME" --current-user powershell.exe -NoLogo -NoProfile -Command \
		'try { $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:4200" -TimeoutSec 5; if ($response.StatusCode -ne 200) { exit 1 }; exit 0 } catch { Write-Error $_; exit 1 }' \
		>/dev/null || die "The tunnel exists, but Cerber cannot load http://localhost:4200."
	echo "OK - Cerber can load http://localhost:4200 from Hades."
}

action="${1:-status}"
if [[ "$action" == "help" || "$action" == "--help" || "$action" == "-h" ]]; then
	usage
	exit 0
fi

case "$action" in
up | down | status) ;;
*)
	usage
	exit 1
	;;
esac

require_cmd curl
require_cmd prlctl
require_cmd python3

[[ -f "$STATIONS_CONFIG" ]] || die "Station inventory not found: $STATIONS_CONFIG"
VM_NAME="${CERBER_VM_NAME:-$(read_cerber_vm_name)}"
require_cerber_running

case "$action" in
up)
	verify_angular_on_hades
	run_tunnel_action up
	verify_angular_from_cerber
	;;
down)
	run_tunnel_action down
	;;
status)
	status_output="$(run_tunnel_action status)"
	printf '%s\n' "$status_output"
	case "$status_output" in
	*"UP - localhost:4200"*) verify_angular_from_cerber ;;
	esac
	;;
esac
