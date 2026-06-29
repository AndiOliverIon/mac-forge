#!/usr/bin/env bash
set -euo pipefail

#######################################
# docker-clean-known-facts.sh
#
# Removes known local Docker leftovers from our publish workflows.
# This is intentionally narrow: only exact, verified artifact names are removed.
#
# Flags:
#   -y, --yes        Skip the confirmation prompt.
#   -n, --dry-run    Show what would be removed, change nothing.
#   -h, --help       Show usage.
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/forge.sh"
fi

die() {
	echo "ERROR: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

usage() {
	sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	exit 0
}

ASSUME_YES=0
DRY_RUN=0

while (($#)); do
	case "$1" in
	-y | --yes) ASSUME_YES=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help) usage ;;
	*) die "Unknown argument: $1 (use --help)" ;;
	esac
	shift
done

require_cmd docker

if ! docker info >/dev/null 2>&1; then
	die "Docker daemon is not reachable. Start Docker Desktop, then re-run."
fi

KNOWN_IMAGES=(
	"portainer.ardis.eu:5000/ardis-timetrack:v2"
	"portainer.ardis.eu:5000/andi-goes-gpt:v1"
)

KNOWN_BUILDX_BUILDERS=(
	"ardis-publish"
)

KNOWN_VOLUMES=(
	"buildx_buildkit_ardis-publish0_state"
)

images=()
builders=()
volumes=()

for image in "${KNOWN_IMAGES[@]}"; do
	if docker image inspect "$image" >/dev/null 2>&1; then
		images+=("$image")
	fi
done

for builder in "${KNOWN_BUILDX_BUILDERS[@]}"; do
	if docker buildx inspect "$builder" >/dev/null 2>&1; then
		builders+=("$builder")
	fi
done

for volume in "${KNOWN_VOLUMES[@]}"; do
	if docker volume inspect "$volume" >/dev/null 2>&1; then
		volumes+=("$volume")
	fi
done

if ((${#images[@]} == 0 && ${#builders[@]} == 0 && ${#volumes[@]} == 0)); then
	echo "Nothing to clean. Known Docker leftovers are not present."
	exit 0
fi

echo "Known Docker leftovers:"
for image in "${images[@]}"; do
	echo "  image:   $image"
done
for builder in "${builders[@]}"; do
	echo "  buildx:  $builder"
done
for volume in "${volumes[@]}"; do
	echo "  volume:  $volume"
done
echo

if ((DRY_RUN)); then
	echo "Dry run. Nothing removed."
	exit 0
fi

if ((ASSUME_YES == 0)); then
	read -r -p "Remove these known Docker leftovers? [y/N]: " ans
	case "${ans:-}" in
	y | Y | yes | YES) ;;
	*)
		echo "Aborted. Nothing removed."
		exit 0
		;;
	esac
fi

for builder in "${builders[@]}"; do
	docker buildx rm "$builder" >/dev/null
	echo "removed buildx builder: $builder"
done

for volume in "${volumes[@]}"; do
	if docker volume inspect "$volume" >/dev/null 2>&1; then
		docker volume rm "$volume" >/dev/null
		echo "removed volume: $volume"
	fi
done

for image in "${images[@]}"; do
	docker image rm "$image" >/dev/null
	echo "removed image: $image"
done

echo "Done."
