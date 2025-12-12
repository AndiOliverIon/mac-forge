#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/../forge.sh"
elif [[ -f "$HOME/mac-forge/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Options
#######################################
DRY_RUN=0
FORCE=0

usage() {
	cat <<EOF
Usage: eject-all [--dry-run] [--force]

--dry-run   Print what would be ejected/unmounted, but do nothing
--force     Use force unmount where possible
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--force)
			FORCE=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown arg: $1"
			usage
			exit 1
			;;
	esac
done

run() {
	if [[ "$DRY_RUN" -eq 1 ]]; then
		echo "[dry-run] $*"
	else
		eval "$@"
	fi
}

#######################################
# Safety: internal volumes to keep
#######################################
is_protected_volume() {
	local name="$1"

	case "$name" in
		"Macintosh HD" | "Macintosh HD - Data" | "System" | "System - Data" | "Recovery" | "Preboot" | "VM")
			return 0
			;;
		*)
			return 1
			;;
	esac
}

#######################################
# Collect volumes to eject
#######################################
declare -a VOLUMES_TO_EJECT=()
declare -a DISKS_TO_EJECT=()

shopt -s nullglob
for vpath in /Volumes/*; do
	[[ -d "$vpath" ]] || continue
	vname="$(basename "$vpath")"

	if is_protected_volume "$vname"; then
		continue
	fi

	VOLUMES_TO_EJECT+=("$vpath")
done
shopt -u nullglob

while IFS= read -r line; do
	disk_id="$(echo "$line" | awk '{print $1}')"
	[[ -n "$disk_id" ]] || continue
	DISKS_TO_EJECT+=("$disk_id")
done < <(diskutil list | awk '
  $1 ~ /^\/dev\/disk[0-9]+$/ && $0 ~ /\(external, physical\):/ { print $1 }
')

#######################################
# Nothing to do?
#######################################
if [[ ${#VOLUMES_TO_EJECT[@]} -eq 0 && ${#DISKS_TO_EJECT[@]} -eq 0 ]]; then
	echo "Nothing to eject."
	exit 0
fi

#######################################
# Present summary & confirm
#######################################
echo
echo "The following will be EJECTED:"
echo "--------------------------------"

for v in "${VOLUMES_TO_EJECT[@]}"; do
	echo "  Volume: $v"
done

for d in "${DISKS_TO_EJECT[@]}"; do
	echo "  Disk:   $d"
done

echo
echo "This requires PHYSICAL reconnect to undo."
echo

if [[ "$DRY_RUN" -eq 0 ]]; then
	read -r -p "Press ENTER to continue, anything else to cancel: " confirm
	if [[ -n "$confirm" ]]; then
		echo "Cancelled."
		exit 0
	fi
else
	echo "[dry-run] Confirmation skipped."
fi

#######################################
# Execute eject
#######################################
for vpath in "${VOLUMES_TO_EJECT[@]}"; do
	echo "Ejecting volume: $vpath"

	if [[ "$FORCE" -eq 1 ]]; then
		run "diskutil unmount force \"$vpath\" >/dev/null 2>&1 || true"
	else
		run "diskutil unmount \"$vpath\" >/dev/null 2>&1 || true"
	fi

	run "diskutil eject \"$vpath\" >/dev/null 2>&1 || true"
done

for disk in "${DISKS_TO_EJECT[@]}"; do
	echo "Ejecting disk: $disk"
	run "diskutil eject \"$disk\" >/dev/null 2>&1 || true"
done

echo "Done."
