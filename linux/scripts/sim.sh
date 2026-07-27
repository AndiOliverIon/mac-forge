#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CYCLE_SECONDS="30"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mac-forge"
CONFIG_FILE="${CONFIG_DIR}/sim-cycle-seconds"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KWIN_TEMPLATE="${SCRIPT_DIR}/sim-kwin.js"
POINTER_SERVICE="${SCRIPT_DIR}/sim-pointer-service.py"
YDOTOOL_SOCKET_DEFAULT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket"

usage() {
	cat <<EOF
Usage:
  sim                 Cycle through the apps open when sim starts
  sim --cycle SECONDS Save a new cycle duration and start cycling
  sim --help          Show this help

The default cycle duration is ${DEFAULT_CYCLE_SECONDS} seconds. Press Ctrl+C to stop.
The app collection is captured once at startup. Each activated app receives a brief
mouse movement without clicks; window state and app content are not changed.
EOF
}

die() {
	echo "Error: $*" >&2
	exit 1
}

is_valid_cycle() {
	[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
		awk -v seconds="$1" 'BEGIN { exit !(seconds > 0) }'
}

find_qdbus() {
	local candidate

	for candidate in \
		qdbus6 \
		qdbus-qt6 \
		qdbus \
		/usr/lib/qt6/bin/qdbus \
		/usr/lib/x86_64-linux-gnu/qt6/bin/qdbus \
		/usr/lib/qt5/bin/qdbus; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done

	return 1
}

require_cmd() {
	local command_name="$1"
	local package_name="${2:-$1}"

	command -v "$command_name" >/dev/null 2>&1 ||
		die "Required command '$command_name' not found. Install the '$package_name' package."
}

check_pointer_injection() {
	local socket="${YDOTOOL_SOCKET:-$YDOTOOL_SOCKET_DEFAULT}"

	require_cmd gdbus libglib2.0-bin
	require_cmd python3 python3
	require_cmd ydotool ydotool
	require_cmd systemctl systemd
	python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio, GLib' \
		>/dev/null 2>&1 ||
		die "Pointer injection requires Python GObject bindings. Install the 'python3-gi' package."

	[[ -e /dev/uinput ]] ||
		die "Pointer injection requires /dev/uinput. Load it with 'sudo modprobe uinput', then restart ydotool.service."
	[[ -r /dev/uinput && -w /dev/uinput ]] ||
		die "Pointer injection requires read/write access to /dev/uinput. Add '$USER' to the input group with 'sudo usermod -aG input $USER', then sign out and back in."
	systemctl --user is-active --quiet ydotool.service ||
		die "Pointer injection requires ydotool.service. Start it with 'systemctl --user enable --now ydotool.service'."
	[[ -S "$socket" ]] ||
		die "ydotool is running but its socket was not found at $socket. Restart it with 'systemctl --user restart ydotool.service'."
	[[ -r "$socket" && -w "$socket" ]] ||
		die "The ydotool socket is not accessible: $socket. Check its ownership and YDOTOOL_SOCKET."
}

cycle_override=""

while (($# > 0)); do
	case "$1" in
	--cycle)
		(($# >= 2)) || die "--cycle requires a number of seconds."
		cycle_override="$2"
		shift 2
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		die "Unknown argument: $1. Run 'sim --help' for usage."
		;;
	esac
done

if [[ -n "$cycle_override" ]]; then
	is_valid_cycle "$cycle_override" ||
		die "Cycle duration must be a number greater than zero."

	mkdir -p "$CONFIG_DIR"
	printf '%s\n' "$cycle_override" >"$CONFIG_FILE"
	cycle_seconds="$cycle_override"
	echo "Saved cycle duration: ${cycle_seconds} seconds."
elif [[ -f "$CONFIG_FILE" ]]; then
	IFS= read -r cycle_seconds <"$CONFIG_FILE" || true
	is_valid_cycle "${cycle_seconds:-}" ||
		die "Saved cycle duration is invalid. Reset it with 'sim --cycle SECONDS'."
else
	cycle_seconds="$DEFAULT_CYCLE_SECONDS"
fi

[[ "$(uname -s)" == "Linux" ]] || die "This sim launcher only runs on Linux."
[[ -f "$KWIN_TEMPLATE" ]] || die "KWin script not found: $KWIN_TEMPLATE"
[[ -f "$POINTER_SERVICE" ]] || die "Pointer service not found: $POINTER_SERVICE"

desktop="${XDG_CURRENT_DESKTOP:-}"
if [[ "${KDE_FULL_SESSION:-}" != "true" && "$desktop" != *KDE* && "$desktop" != *Plasma* ]]; then
	die "A KDE Plasma session is required; detected desktop: ${desktop:-unknown}."
fi

qdbus_cmd="$(find_qdbus)" ||
	die "A Qt D-Bus client is required. Install the qdbus package for your Plasma version."

check_pointer_injection

if ! "$qdbus_cmd" org.kde.KWin /Scripting >/dev/null 2>&1; then
	die "Could not reach KWin's scripting service in this Plasma session."
fi

cycle_milliseconds="$(
	awk -v seconds="$cycle_seconds" 'BEGIN { printf "%.0f", seconds * 1000 }'
)"
((cycle_milliseconds > 0)) || die "Cycle duration is too small."

runtime_root="${XDG_RUNTIME_DIR:-/tmp}"
runtime_dir="$(mktemp -d "${runtime_root%/}/mac-forge-sim.XXXXXX")"
runtime_script="${runtime_dir}/sim.js"
script_name="mac-forge-sim-$$"
pointer_service_name="io.github.AndiOliverIon.MacForge.Sim.P$$"
script_id=""
pointer_service_pid=""

cleanup() {
	if [[ -n "$pointer_service_pid" ]]; then
		kill "$pointer_service_pid" >/dev/null 2>&1 || true
		wait "$pointer_service_pid" 2>/dev/null || true
	fi

	if [[ -n "$script_id" ]]; then
		"$qdbus_cmd" \
			org.kde.KWin \
			"/Scripting/Script${script_id}" \
			org.kde.kwin.Script.stop \
			>/dev/null 2>&1 || true
		"$qdbus_cmd" \
			org.kde.KWin \
			/Scripting \
			org.kde.kwin.Scripting.unloadScript \
			"$script_name" \
			>/dev/null 2>&1 || true
	fi

	if [[ -f "$runtime_script" ]]; then
		rm -f -- "$runtime_script"
	fi
	if [[ -d "$runtime_dir" ]]; then
		rmdir -- "$runtime_dir" 2>/dev/null || true
	fi
}

stop_sim() {
	printf '\nStopped sim.\n'
	exit 130
}

trap cleanup EXIT
trap stop_sim INT TERM

sed \
	-e "s/__SIM_CYCLE_MILLISECONDS__/${cycle_milliseconds}/g" \
	-e "s/__SIM_DBUS_SERVICE__/${pointer_service_name}/g" \
	"$KWIN_TEMPLATE" >"$runtime_script"

python3 "$POINTER_SERVICE" "$pointer_service_name" "$$" &
pointer_service_pid="$!"
if ! gdbus wait --session --timeout 3 "$pointer_service_name"; then
	die "Could not start the private sim pointer service."
fi
kill -0 "$pointer_service_pid" >/dev/null 2>&1 ||
	die "The private sim pointer service exited unexpectedly."

if ! script_id="$(
	"$qdbus_cmd" \
		org.kde.KWin \
		/Scripting \
		org.kde.kwin.Scripting.loadScript \
		"$runtime_script" \
		"$script_name"
)"; then
	die "KWin rejected the sim script."
fi

script_id="${script_id//$'\r'/}"
[[ "$script_id" =~ ^[0-9]+$ ]] ||
	die "KWin returned an invalid script id: ${script_id:-empty}."

if ! "$qdbus_cmd" \
	org.kde.KWin \
	"/Scripting/Script${script_id}" \
	org.kde.kwin.Script.run \
	>/dev/null; then
	die "KWin could not start the sim script."
fi

echo "KWin app cycle with mouse movement started every ${cycle_seconds} seconds."
echo "Press Ctrl+C to stop and unload it."

while true; do
	sleep 3600
done
