#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CYCLE_SECONDS="30"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mac-forge"
CONFIG_FILE="${CONFIG_DIR}/sim-cycle-seconds"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KWIN_TEMPLATE="${SCRIPT_DIR}/sim-kwin.js"

usage() {
	cat <<EOF
Usage:
  sim                 Cycle through the apps open when sim starts
  sim --cycle SECONDS Save a new cycle duration and start cycling
  sim --help          Show this help

The default cycle duration is ${DEFAULT_CYCLE_SECONDS} seconds. Press Ctrl+C to stop.
The app collection is captured once at startup; window state is not changed.
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

desktop="${XDG_CURRENT_DESKTOP:-}"
if [[ "${KDE_FULL_SESSION:-}" != "true" && "$desktop" != *KDE* && "$desktop" != *Plasma* ]]; then
	die "A KDE Plasma session is required; detected desktop: ${desktop:-unknown}."
fi

qdbus_cmd="$(find_qdbus)" ||
	die "A Qt D-Bus client is required. Install the qdbus package for your Plasma version."

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
script_id=""

cleanup() {
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

sed "s/__SIM_CYCLE_MILLISECONDS__/${cycle_milliseconds}/g" \
	"$KWIN_TEMPLATE" >"$runtime_script"

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

echo "KWin app cycle started every ${cycle_seconds} seconds."
echo "Press Ctrl+C to stop and unload it."

while true; do
	sleep 3600
done
