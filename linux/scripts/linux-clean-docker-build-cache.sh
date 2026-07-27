#!/usr/bin/env bash
set -euo pipefail

CACHE_AGE_FILTER="until=168h"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: linux-clean-docker-build-cache [--dry-run]

Remove reclaimable Docker BuildKit cache unused for seven days. Containers,
images, volumes, networks, builders, configuration, credentials, and SQL data
are never pruned.
EOF
}

main() {
  local dry_run=0

  (( $# <= 1 )) || die "Too many arguments (use --help)"
  case "${1:-}" in
    "") ;;
    -n | --dry-run) dry_run=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use --help)" ;;
  esac

  [[ "$(uname -s)" == "Linux" ]] || die "This cleaner only runs on Linux."
  command -v docker >/dev/null 2>&1 || { echo "Docker CLI is not installed; skipping."; exit 0; }
  docker buildx version >/dev/null 2>&1 || { echo "Docker Buildx is unavailable; skipping."; exit 0; }
  docker info >/dev/null 2>&1 || { echo "Docker is offline or inaccessible; skipping."; exit 0; }

  if (( dry_run )); then
    echo "Docker build-cache records unused for more than seven days:"
    docker buildx du --filter "$CACHE_AGE_FILTER"
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  docker buildx prune --filter "$CACHE_AGE_FILTER" --force
}

main "$@"
