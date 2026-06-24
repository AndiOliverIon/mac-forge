#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# docker-cleanup.sh
#
# Removes every local Docker image that is NOT used by a currently running
# container. Images backing running containers (e.g. the forge-sql SQL Server
# container) are always protected.
#
# Flags:
#   -y, --yes        Skip the confirmation prompt.
#   -n, --dry-run    Show what would be removed, change nothing.
#   -f, --force      Pass --force to `docker rmi` (also removes images that are
#                    referenced by STOPPED containers). Use with care.
#   -h, --help       Show usage.
#######################################

#######################################
# Load forge config (if present)
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/forge.sh"
fi

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

usage() {
	sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	exit 0
}

#######################################
# Args
#######################################
ASSUME_YES=0
DRY_RUN=0
FORCE=0

while (($#)); do
	case "$1" in
	-y | --yes) ASSUME_YES=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-f | --force) FORCE=1 ;;
	-h | --help) usage ;;
	*) die "Unknown argument: $1 (use --help)" ;;
	esac
	shift
done

#######################################
# Ensure Docker daemon is running
#######################################
ensure_docker_running() {
	require_cmd docker

	if docker info >/dev/null 2>&1; then
		return 0
	fi

	echo "Docker daemon not reachable. Starting Docker Desktop..."
	if command -v open >/dev/null 2>&1; then
		open -g -a Docker || open -a Docker || true
	fi

	echo "Waiting for Docker to become ready..."
	local max_tries=60 i
	for ((i = 1; i <= max_tries; i++)); do
		if docker info >/dev/null 2>&1; then
			echo "Docker is ready (attempt $i)."
			return 0
		fi
		echo "  ... not ready yet (attempt $i), retrying in 2s"
		sleep 2
	done

	die "Docker daemon did not become ready in time."
}

ensure_docker_running

#######################################
# Collect protected image IDs (images used by RUNNING containers)
#######################################
declare -A PROTECTED=()
PROTECTED_NAMES=""

while IFS=$'\t' read -r cname cimage; do
	[[ -z "$cname" ]] && continue
	# Resolve the running container's image to its full image ID.
	iid="$(docker inspect --format '{{.Image}}' "$cname" 2>/dev/null || true)"
	[[ -z "$iid" ]] && continue
	PROTECTED["$iid"]=1
	PROTECTED_NAMES+="  • ${cname}  →  ${cimage}"$'\n'
done < <(docker ps --format '{{.Names}}\t{{.Image}}')

if ((${#PROTECTED[@]} == 0)); then
	echo "⚠ No running containers found — nothing is protected."
	echo "  Refusing to bulk-delete images without a running container to anchor on."
	echo "  Start the container you want to keep first, then re-run."
	exit 1
fi

echo "🔒 Protected images (running containers):"
printf '%s' "$PROTECTED_NAMES"
echo

#######################################
# Determine removable images (all images minus protected)
#######################################
REMOVABLE=()
while read -r iid; do
	[[ -z "$iid" ]] && continue
	[[ -n "${PROTECTED[$iid]:-}" ]] && continue
	REMOVABLE+=("$iid")
done < <(docker images --no-trunc --format '{{.ID}}' | sort -u)

if ((${#REMOVABLE[@]} == 0)); then
	echo "✅ Nothing to clean. Only protected images are present."
	exit 0
fi

#######################################
# Show what will be removed
#######################################
echo "🧹 Images to remove (${#REMOVABLE[@]}):"
for iid in "${REMOVABLE[@]}"; do
	# List every repo:tag pointing at this image ID.
	docker images --no-trunc --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}' |
		awk -F'\t' -v id="$iid" '$1==id { printf "  • %-45s %s\n", $2, $3 }'
done
echo

if ((DRY_RUN)); then
	echo "ℹ Dry run — no images were removed."
	exit 0
fi

#######################################
# Confirm (destructive)
#######################################
if ((ASSUME_YES == 0)); then
	read -r -p "Remove these ${#REMOVABLE[@]} image(s)? [y/N]: " ans
	case "${ans:-}" in
	y | Y | yes | YES) ;;
	*)
		echo "Aborted. Nothing removed."
		exit 0
		;;
	esac
fi

#######################################
# Remove
#######################################
RMI_ARGS=()
((FORCE)) && RMI_ARGS+=(--force)

FAILED=0
for iid in "${REMOVABLE[@]}"; do
	if docker rmi "${RMI_ARGS[@]}" "$iid" >/dev/null 2>&1; then
		echo "  ✓ removed $iid"
	else
		echo "  ✗ could not remove $iid (likely used by a stopped container — re-run with --force)"
		FAILED=1
	fi
done

echo
if ((FAILED)); then
	echo "⚠ Done with some skips. Re-run with --force to remove images held by stopped containers."
else
	echo "✅ Done. All non-running-container images removed."
fi
