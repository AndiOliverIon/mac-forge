#!/usr/bin/env bash
set -euo pipefail

USER_SIM_ROOT="$HOME/Library/Developer/CoreSimulator"
USER_SIM_CACHE="$USER_SIM_ROOT/Caches"
USER_SIM_TEMP="$USER_SIM_ROOT/Temp"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-xcode-simulators [--dry-run]

Clear the current user's CoreSimulator caches and temp files. Xcode rebuilds
them on the next simulator launch. Simulator devices, installed apps, runtime
images, XCTest clones, DeviceSupport symbol packs, archives, and Xcode
settings are left in place.

Options:
  -n, --dry-run Show the cleanup actions and sizes without changing anything.
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
    die "$process_name is running. Close it before cleaning CoreSimulator caches."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the $process_name process state."
  fi
}

format_gib_from_kib() {
  awk -v k="$1" 'BEGIN {
    if (k < 0) k = 0
    printf "%.2f GiB", k / 1048576
  }'
}

known_user_tree_is_safe() {
  local candidate="$1"
  local expected="$2"
  local uid="$3"

  [[ "$candidate" == "$expected" ]] || return 1
  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

print_preview() {
  local cache_kib=0
  local temp_kib=0

  echo "Xcode simulator cache cleanup:"
  echo "  - Clear user CoreSimulator Caches and Temp if present."

  if [[ -d "$USER_SIM_CACHE" && ! -L "$USER_SIM_CACHE" ]]; then
    cache_kib="$(du -sk "$USER_SIM_CACHE" | awk '{print $1}')"
    printf '      caches: %s\n' "$(format_gib_from_kib "$cache_kib")"
  else
    echo "      caches: none"
  fi

  if [[ -d "$USER_SIM_TEMP" && ! -L "$USER_SIM_TEMP" ]]; then
    temp_kib="$(du -sk "$USER_SIM_TEMP" | awk '{print $1}')"
    printf '      temp: %s\n' "$(format_gib_from_kib "$temp_kib")"
  else
    echo "      temp: none"
  fi

  echo "  - Keep simulator devices, runtime images, archives, and DeviceSupport."
}

delete_user_tree() {
  local candidate="$1"
  local expected="$2"
  local uid="$3"

  known_user_tree_is_safe "$candidate" "$expected" "$uid" || return 0
  echo "Deleting: $candidate"
  rm -rf -- "$candidate"
}

main() {
  local dry_run=0
  local uid

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-xcode-simulators only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$USER_SIM_CACHE" && ! -d "$USER_SIM_TEMP" ]]; then
    echo "CoreSimulator caches and temp are not present."
    exit 0
  fi

  uid="$(id -u)"
  print_preview

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  require_inactive Xcode
  require_inactive Simulator
  require_inactive xcodebuild
  require_inactive XCBBuildService
  require_inactive xctest

  delete_user_tree "$USER_SIM_CACHE" "$USER_SIM_CACHE" "$uid"
  delete_user_tree "$USER_SIM_TEMP" "$USER_SIM_TEMP" "$uid"

  echo "Xcode simulator cache cleanup completed."
}

main "$@"
