#!/usr/bin/env bash
set -euo pipefail

XCTEST_DEVICES_DIR="$HOME/Library/Developer/XCTestDevices"
USER_SIM_ROOT="$HOME/Library/Developer/CoreSimulator"
USER_SIM_CACHE="$USER_SIM_ROOT/Caches"
USER_SIM_TEMP="$USER_SIM_ROOT/Temp"

RUNTIME_IDS=()
RUNTIME_LABELS=()
RUNTIME_BYTES=()
CLONE_PATHS=()
CLONE_NAMES=()
CLONE_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-xcode-simulators [--dry-run]

Remove iPhone and iPad simulator state so the disk can be reclaimed when you
are not working in Xcode. This quits Simulator, deletes every simulator
device, deletes verified XCTest clones, and deletes iOS simulator runtimes.
Xcode recopies runtimes the next time you download them; device contents are
not restored.

watchOS/tvOS runtimes, DeviceSupport symbol packs, archives, and Xcode
settings are not touched.

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
    die "$process_name is running. Close it before cleaning Xcode simulators."
  else
    pgrep_status=$?
    (( pgrep_status == 1 )) || die "Could not inspect the $process_name process state."
  fi
}

quit_simulator() {
  local attempt

  if ! pgrep -x Simulator >/dev/null 2>&1; then
    echo "Simulator app is not running."
    return
  fi

  echo "Closing Simulator app..."
  pkill -x Simulator

  for attempt in 1 2 3 4 5; do
    if ! pgrep -x Simulator >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  die "Simulator app did not close."
}

format_gib_from_bytes() {
  awk -v b="$1" 'BEGIN {
    if (b < 0) b = 0
    printf "%.2f GiB", b / 1073741824
  }'
}

format_gib_from_kib() {
  awk -v k="$1" 'BEGIN {
    if (k < 0) k = 0
    printf "%.2f GiB", k / 1048576
  }'
}

collect_ios_runtimes() {
  local line
  local ident
  local label
  local bytes

  RUNTIME_IDS=()
  RUNTIME_LABELS=()
  RUNTIME_BYTES=()

  while IFS=$'\t' read -r ident label bytes; do
    [[ -n "$ident" ]] || continue
    RUNTIME_IDS+=("$ident")
    RUNTIME_LABELS+=("$label")
    RUNTIME_BYTES+=("$bytes")
  done < <(
    xcrun simctl runtime list -j | python3 -c '
import json, sys

data = json.load(sys.stdin)
if not isinstance(data, dict):
    raise SystemExit("unexpected simctl runtime JSON")

for ident, info in data.items():
    if not isinstance(info, dict):
        continue
    if info.get("platformIdentifier") != "com.apple.platform.iphonesimulator":
        continue
    rid = str(info.get("runtimeIdentifier") or "")
    tail = rid.rsplit(".", 1)[-1]
    parts = tail.split("-")
    if len(parts) >= 2:
        name = parts[0] + " " + ".".join(parts[1:])
    else:
        name = tail or "iOS"
    build = str(info.get("build") or "")
    label = f"{name} ({build})" if build else name
    size = info.get("sizeBytes") or 0
    try:
        size = int(size)
    except (TypeError, ValueError):
        size = 0
    deletable = info.get("deletable")
    flag = "" if deletable else " [not deletable]"
    print(f"{ident}\t{label}{flag}\t{size}")
'
  )
}

collect_test_clones() {
  local candidate
  local clone_name
  local size_kib

  CLONE_PATHS=()
  CLONE_NAMES=()
  CLONE_SIZES_KIB=()

  [[ -d "$XCTEST_DEVICES_DIR" && ! -L "$XCTEST_DEVICES_DIR" ]] || return 0

  while IFS= read -r -d '' candidate; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    [[ -f "$candidate/device.plist" ]] || continue

    clone_name="$(plutil -extract name raw "$candidate/device.plist" 2>/dev/null || true)"
    [[ "$clone_name" == Clone\ *\ of\ * ]] || continue

    size_kib="$(du -sk "$candidate" | awk '{print $1}')"
    CLONE_PATHS+=("$candidate")
    CLONE_NAMES+=("$clone_name")
    CLONE_SIZES_KIB+=("$size_kib")
  done < <(find "$XCTEST_DEVICES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
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
  local index
  local clone_kib=0
  local devices_kib=0
  local cache_kib=0
  local temp_kib=0

  echo "Xcode iPhone/iPad simulator cleanup:"
  echo "  - Quit Simulator if it is running."
  echo "  - Shut down and delete all simulator devices."

  if [[ -d "$USER_SIM_ROOT/Devices" ]]; then
    devices_kib="$(du -sk "$USER_SIM_ROOT/Devices" | awk '{print $1}')"
    printf '      devices currently: %s\n' "$(format_gib_from_kib "$devices_kib")"
  fi

  echo "  - Delete verified XCTest parallel-test clones (all ages)."
  if (( ${#CLONE_PATHS[@]} == 0 )); then
    echo "      clones: none"
  else
    for index in "${!CLONE_SIZES_KIB[@]}"; do
      clone_kib="$((clone_kib + CLONE_SIZES_KIB[index]))"
    done
    printf '      clones: %d (%s)\n' "${#CLONE_PATHS[@]}" "$(format_gib_from_kib "$clone_kib")"
  fi

  echo "  - Delete iOS simulator runtimes (re-download in Xcode when you return):"
  if (( ${#RUNTIME_IDS[@]} == 0 )); then
    echo "      runtimes: none"
  else
    for index in "${!RUNTIME_IDS[@]}"; do
      printf '      - %s  %s\n' \
        "${RUNTIME_LABELS[$index]}" \
        "$(format_gib_from_bytes "${RUNTIME_BYTES[$index]}")"
    done
  fi

  echo "  - Clear user CoreSimulator Caches and Temp if present."
  if [[ -d "$USER_SIM_CACHE" ]]; then
    cache_kib="$(du -sk "$USER_SIM_CACHE" | awk '{print $1}')"
    printf '      caches: %s\n' "$(format_gib_from_kib "$cache_kib")"
  fi
  if [[ -d "$USER_SIM_TEMP" ]]; then
    temp_kib="$(du -sk "$USER_SIM_TEMP" | awk '{print $1}')"
    printf '      temp: %s\n' "$(format_gib_from_kib "$temp_kib")"
  fi

  echo "  - Keep Xcode, archives, DeviceSupport, and watchOS/tvOS runtimes."
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
  local index
  local ident
  local label

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
  require_cmd pkill
  require_cmd plutil
  require_cmd python3
  require_cmd rm
  require_cmd stat
  require_cmd xcrun
  xcrun --find simctl >/dev/null 2>&1 || die "simctl is not available."

  uid="$(id -u)"
  collect_ios_runtimes
  collect_test_clones
  print_preview

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  require_inactive Xcode
  require_inactive xcodebuild
  require_inactive xctest
  quit_simulator

  echo "Shutting down all simulator devices..."
  xcrun simctl shutdown all

  echo "Deleting all simulator devices..."
  xcrun simctl delete all

  for index in "${!CLONE_PATHS[@]}"; do
    case "${CLONE_PATHS[$index]}" in
      "$XCTEST_DEVICES_DIR/"*) ;;
      *) die "Refusing target outside Xcode test-clone directory: ${CLONE_PATHS[$index]}" ;;
    esac
    [[ -d "${CLONE_PATHS[$index]}" && ! -L "${CLONE_PATHS[$index]}" ]] || continue
    echo "Deleting clone: ${CLONE_NAMES[$index]}"
    rm -rf -- "${CLONE_PATHS[$index]}"
  done

  for index in "${!RUNTIME_IDS[@]}"; do
    ident="${RUNTIME_IDS[$index]}"
    label="${RUNTIME_LABELS[$index]}"
    case "$label" in
      *" [not deletable]")
        echo "Skipping runtime that simctl marked not deletable: $label"
        continue
        ;;
    esac
    echo "Deleting iOS simulator runtime: $label"
    xcrun simctl runtime delete "$ident"
  done

  delete_user_tree "$USER_SIM_CACHE" "$USER_SIM_CACHE" "$uid"
  delete_user_tree "$USER_SIM_TEMP" "$USER_SIM_TEMP" "$uid"

  echo "Xcode iPhone/iPad simulator cleanup completed."
}

main "$@"
