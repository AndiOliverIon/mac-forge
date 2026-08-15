#!/usr/bin/env bash
set -euo pipefail

DEVICE_SUPPORT_DIR="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
RETENTION_MINUTES=43200
RETENTION_DAYS=30

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-xcode-device-support [--dry-run]

Delete Xcode iOS DeviceSupport symbol bundles whose entire contents are older
than thirty days. These per-iOS-version bundles are regenerated automatically
the next time a matching device is connected. Recently used bundles, archives,
settings, and source code are preserved.

Options:
  -n, --dry-run Show eligible bundles and their reported size without deleting.
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
    die "$process_name is running. Close it before cleaning iOS DeviceSupport."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the $process_name process state."
  fi
}

candidate_is_safe() {
  local candidate="$1"
  local uid="$2"

  [[ "$candidate" == "$DEVICE_SUPPORT_DIR/"* ]] || return 1
  [[ -e "$candidate" ]] || return 1
  [[ ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  if find "$candidate" -mmin "-$RETENTION_MINUTES" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

collect_targets() {
  local uid="$1"
  local candidate
  local size_kib

  while IFS= read -r -d '' candidate; do
    if candidate_is_safe "$candidate" "$uid"; then
      size_kib="$(du -sk "$candidate" | awk '{print $1}')"
      TARGETS+=("$candidate")
      TARGET_SIZES_KIB+=("$size_kib")
    fi
  done < <(find "$DEVICE_SUPPORT_DIR" -mindepth 1 -maxdepth 1 -user "$uid" -print0)
}

main() {
  local dry_run=0
  local uid
  local index
  local target
  local total_kib=0
  local deleted=0
  local skipped=0

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-xcode-device-support only runs on macOS."

  require_cmd awk
  require_cmd basename
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$DEVICE_SUPPORT_DIR" ]]; then
    echo "Xcode iOS DeviceSupport directory does not exist."
    exit 0
  fi
  [[ ! -L "$DEVICE_SUPPORT_DIR" ]] || die "Refusing symlinked iOS DeviceSupport directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "No iOS DeviceSupport bundles are entirely older than $RETENTION_DAYS days."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'iOS DeviceSupport bundles entirely older than %d days: %d entries (reported %.2f GiB)\n' \
    "$RETENTION_DAYS" "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  for index in "${!TARGETS[@]}"; do
    printf '  - %s (%.2f GiB)\n' \
      "$(basename "${TARGETS[$index]}")" \
      "$(awk -v kib="${TARGET_SIZES_KIB[$index]}" 'BEGIN { print kib / 1048576 }')"
  done

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  require_inactive Xcode
  require_inactive xcodebuild

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if candidate_is_safe "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Deleted: $deleted"
  echo "Skipped after final safety check: $skipped"
}

main "$@"
