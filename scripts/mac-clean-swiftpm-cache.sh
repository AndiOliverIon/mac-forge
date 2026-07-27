#!/usr/bin/env bash
set -euo pipefail

SWIFTPM_CACHE_DIR="$HOME/Library/Caches/org.swift.swiftpm/repositories"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-swiftpm-cache [--dry-run]

Purge Swift Package Manager's global repository cache using SwiftPM's own
command. Package.resolved, project-local .build folders, package collections,
security fingerprints, configuration, and credentials are preserved.

Options:
  -n, --dry-run Show the repository-cache location and size without changing it.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

require_inactive() {
  local process_name="$1"
  local pgrep_status

  if pgrep -x "$process_name" >/dev/null 2>&1; then
    die "$process_name is running. Close it before purging the SwiftPM cache."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the $process_name process state."
  fi
}

cache_size_kib() {
  if [[ -d "$SWIFTPM_CACHE_DIR" ]]; then
    du -sk "$SWIFTPM_CACHE_DIR" | awk '{print $1}'
  else
    echo 0
  fi
}

format_gib() {
  awk -v kib="$1" 'BEGIN { printf "%.2f GiB", kib / 1048576 }'
}

main() {
  local dry_run=0
  local before_kib
  local after_kib
  local reclaimed_kib
  local process_name

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-swiftpm-cache only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd pgrep
  require_cmd swift

  before_kib="$(cache_size_kib)"

  if (( dry_run )); then
    echo "SwiftPM global repository-cache preview:"
    echo "  Location: $SWIFTPM_CACHE_DIR"
    echo "  Reported size: $(format_gib "$before_kib")"
    echo "  Action: swift package purge-cache"
    exit 0
  fi

  for process_name in Xcode xcodebuild XCBBuildService swift swift-build swift-package swift-frontend; do
    require_inactive "$process_name"
  done

  echo "Purging SwiftPM global repository cache..."
  swift package purge-cache

  after_kib="$(cache_size_kib)"
  if (( before_kib > after_kib )); then
    reclaimed_kib="$((before_kib - after_kib))"
  else
    reclaimed_kib=0
  fi

  echo "SwiftPM repository cache before: $(format_gib "$before_kib")"
  echo "SwiftPM repository cache after:  $(format_gib "$after_kib")"
  echo "Reclaimed:                       $(format_gib "$reclaimed_kib")"
}

main "$@"
