#!/usr/bin/env bash
set -euo pipefail

YARN_CACHE_ROOT="$HOME/Library/Caches/Yarn"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-yarn-cache [--dry-run]

Clear Yarn v1's downloaded package cache using Yarn's own command. Projects,
lockfiles, node_modules, global packages, configuration, and registry
credentials are preserved.

Options:
  -n, --dry-run Show the cache location and reported size without changing it.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

require_yarn_inactive() {
  local pgrep_status
  local yarn_process_pattern='(^|[ /])yarn(pkg)?(\.js)?([[:space:]]|$)'

  if pgrep -f "$yarn_process_pattern" >/dev/null 2>&1; then
    die "Yarn is running. Let it finish before cleaning the package cache."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the Yarn process state."
  fi
}

cache_size_kib() {
  if [[ -d "$YARN_CACHE_ROOT" ]]; then
    du -sk "$YARN_CACHE_ROOT" | awk '{print $1}'
  else
    echo 0
  fi
}

format_gib() {
  awk -v kib="$1" 'BEGIN { printf "%.2f GiB", kib / 1048576 }'
}

main() {
  local dry_run=0
  local cache_dir
  local before_kib
  local after_kib
  local reclaimed_kib
  local yarn_version

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-yarn-cache only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd pgrep
  require_cmd yarn

  yarn_version="$(yarn --version)"
  [[ "$yarn_version" == 1.* ]] || die "Expected Yarn v1, found: $yarn_version"

  cache_dir="$(yarn --cache-folder "$YARN_CACHE_ROOT" cache dir)"
  [[ "$cache_dir" == "$YARN_CACHE_ROOT/"* ]] || die "Unexpected Yarn cache path: $cache_dir"

  before_kib="$(cache_size_kib)"

  if (( dry_run )); then
    echo "Yarn v1 package-cache preview:"
    echo "  Location: $cache_dir"
    echo "  Reported size: $(format_gib "$before_kib")"
    echo "  Action: yarn --cache-folder $YARN_CACHE_ROOT cache clean"
    exit 0
  fi

  require_yarn_inactive

  echo "Cleaning Yarn v1 package cache: $cache_dir"
  yarn --cache-folder "$YARN_CACHE_ROOT" cache clean

  after_kib="$(cache_size_kib)"
  if (( before_kib > after_kib )); then
    reclaimed_kib="$((before_kib - after_kib))"
  else
    reclaimed_kib=0
  fi

  echo "Yarn cache before: $(format_gib "$before_kib")"
  echo "Yarn cache after:  $(format_gib "$after_kib")"
  echo "Reclaimed:         $(format_gib "$reclaimed_kib")"
}

main "$@"
