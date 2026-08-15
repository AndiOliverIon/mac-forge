#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-go-build-cache [--dry-run]

Clear the Go build cache (GOCACHE). This holds compiled build artifacts only
and is rebuilt on demand. The module cache (GOMODCACHE / go/pkg/mod) is not
touched, so no packages need to be re-downloaded.

Options:
  -n, --dry-run Show the cache location and reported size without clearing it.
  -h, --help    Show this help.
EOF
}

main() {
  local dry_run=0
  local cache_dir
  local size

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-go-build-cache only runs on macOS."
  command -v go >/dev/null 2>&1 || die "Go is not installed."

  cache_dir="$(go env GOCACHE 2>/dev/null || true)"
  if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
    echo "Go build cache directory does not exist."
    exit 0
  fi

  size="$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')"

  if (( dry_run )); then
    echo "Go build cache: $cache_dir ($size)"
    echo "Dry run: nothing was cleared."
    exit 0
  fi

  echo "Clearing Go build cache: $cache_dir ($size)..."
  go clean -cache
  echo "✓ Go build cache cleared."
}

main "$@"
