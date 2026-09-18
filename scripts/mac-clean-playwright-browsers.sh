#!/usr/bin/env bash
set -euo pipefail

PLAYWRIGHT_CACHE_DIR="$HOME/Library/Caches/ms-playwright"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-playwright-browsers [--dry-run]

Delete Playwright's downloaded browser binaries. Projects, tests, and npm
packages are preserved; the next Playwright run reinstalls browsers with
`npx playwright install`.

The cleanup is skipped when a process is using the Playwright cache.

Options:
  -n, --dry-run Show the cache location and size without deleting it.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

cache_is_in_use() {
  local pgrep_status
  local lsof_status

  if pgrep -f "$PLAYWRIGHT_CACHE_DIR" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi
  (( pgrep_status == 1 )) || return 2

  if lsof -n -P +D "$PLAYWRIGHT_CACHE_DIR" >/dev/null 2>&1; then
    return 0
  else
    lsof_status=$?
  fi
  (( lsof_status == 1 )) && return 1
  return 2
}

tree_is_safe() {
  local candidate="$1"
  local uid="$2"

  [[ "$candidate" == "$PLAYWRIGHT_CACHE_DIR" ]] || return 1
  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

main() {
  local dry_run=0
  local uid
  local size
  local in_use_status

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-playwright-browsers only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd lsof
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$PLAYWRIGHT_CACHE_DIR" ]]; then
    echo "Playwright browser cache does not exist."
    exit 0
  fi
  [[ ! -L "$PLAYWRIGHT_CACHE_DIR" ]] || die "Refusing symlinked Playwright cache directory."

  uid="$(id -u)"
  tree_is_safe "$PLAYWRIGHT_CACHE_DIR" "$uid" || die "Playwright cache is not safe to delete."

  size="$(du -sh "$PLAYWRIGHT_CACHE_DIR" 2>/dev/null | awk '{print $1}')"
  echo "Playwright browsers: $PLAYWRIGHT_CACHE_DIR ($size)"

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  if cache_is_in_use; then
    echo "Playwright browsers are in use; skipping."
    exit 0
  else
    in_use_status=$?
  fi
  (( in_use_status == 1 )) || die "Could not inspect Playwright cache use."

  rm -rf -- "$PLAYWRIGHT_CACHE_DIR"
  echo "✓ Playwright browser cache deleted."
}

main "$@"
