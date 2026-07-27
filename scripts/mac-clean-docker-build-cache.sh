#!/usr/bin/env bash
set -euo pipefail

CACHE_AGE_FILTER="until=168h"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-docker-build-cache [--dry-run]

Remove reclaimable Docker BuildKit cache that has not been used in seven days.
Containers, images, volumes, networks, builders, Docker configuration, and
credentials are never pruned. Docker Desktop is not started automatically.

Options:
  -n, --dry-run Show eligible build-cache records without deleting them.
  -h, --help    Show this help.
EOF
}

main() {
  local dry_run=0

  (( $# <= 1 )) || die "Too many arguments (use --help)"

  case "${1:-}" in
    "")
      ;;
    -n | --dry-run)
      dry_run=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-docker-build-cache only runs on macOS."
  command -v docker >/dev/null 2>&1 || die "Docker CLI is not installed."
  docker buildx version >/dev/null 2>&1 || die "Docker Buildx is not available."

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is offline; skipping build-cache cleanup."
    exit 0
  fi

  if (( dry_run )); then
    echo "Docker build-cache records unused for more than seven days:"
    docker buildx du --filter "$CACHE_AGE_FILTER"
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  echo "Pruning Docker build cache unused for more than seven days..."
  docker buildx prune --filter "$CACHE_AGE_FILTER" --force
}

main "$@"
