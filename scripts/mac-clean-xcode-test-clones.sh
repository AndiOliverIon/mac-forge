#!/usr/bin/env bash
set -euo pipefail

XCTEST_DEVICES_DIR="$HOME/Library/Developer/XCTestDevices"
RETENTION_DAYS=7

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-xcode-test-clones [--dry-run]

Delete verified Xcode parallel-test simulator clones older than seven days.
Normal simulators, runtimes, Xcode settings, and unverified folders are kept.

Options:
  -n, --dry-run Show eligible clones and their reported size without deleting.
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
    die "$process_name is running. Close it before cleaning Xcode test clones."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the $process_name process state."
  fi
}

collect_targets() {
  local cutoff_epoch="$1"
  local candidate
  local candidate_epoch
  local clone_name
  local size_kib

  while IFS= read -r -d '' candidate; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    [[ -f "$candidate/device.plist" ]] || continue

    clone_name="$(plutil -extract name raw "$candidate/device.plist" 2>/dev/null || true)"
    [[ "$clone_name" == Clone\ *\ of\ * ]] || continue

    candidate_epoch="$(stat -f '%m' "$candidate")"
    (( candidate_epoch < cutoff_epoch )) || continue

    size_kib="$(du -sk "$candidate" | awk '{print $1}')"
    TARGETS+=("$candidate")
    TARGET_NAMES+=("$clone_name")
    TARGET_SIZES_KIB+=("$size_kib")
  done < <(find "$XCTEST_DEVICES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
}

main() {
  local dry_run=0
  local cutoff_epoch
  local index
  local total_kib=0
  local target

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-xcode-test-clones only runs on macOS."

  require_cmd awk
  require_cmd date
  require_cmd du
  require_cmd find
  require_cmd pgrep
  require_cmd plutil
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$XCTEST_DEVICES_DIR" ]]; then
    echo "Xcode test-clone directory does not exist."
    exit 0
  fi
  [[ ! -L "$XCTEST_DEVICES_DIR" ]] || die "Refusing symlinked Xcode test-clone directory."

  TARGETS=()
  TARGET_NAMES=()
  TARGET_SIZES_KIB=()

  cutoff_epoch="$(( $(date +%s) - RETENTION_DAYS * 86400 ))"
  collect_targets "$cutoff_epoch"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "No verified Xcode test clones older than $RETENTION_DAYS days."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'Verified Xcode test clones older than %d days: %d (reported %.1f GiB)\n' \
    "$RETENTION_DAYS" "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  if (( dry_run )); then
    for index in "${!TARGETS[@]}"; do
      printf '  - %s -> %s\n' "${TARGET_NAMES[$index]}" "${TARGETS[$index]}"
    done
    exit 0
  fi

  require_inactive Xcode
  require_inactive Simulator
  require_inactive xcodebuild
  require_inactive xctest

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    case "$target" in
      "$XCTEST_DEVICES_DIR/"*) ;;
      *) die "Refusing target outside Xcode test-clone directory: $target" ;;
    esac

    [[ -d "$target" && ! -L "$target" ]] || die "Clone changed during cleanup: $target"
    echo "Deleting: ${TARGET_NAMES[$index]}"
    rm -rf -- "$target"
  done

  echo "Xcode test-clone cleanup completed."
}

main "$@"
