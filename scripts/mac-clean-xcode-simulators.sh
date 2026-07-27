#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-xcode-simulators [--dry-run]

Quit Simulator, shut down all devices, delete unavailable devices, and erase
the contents and settings of every remaining simulator device.

Options:
  -n, --dry-run Show the cleanup actions without changing anything.
  -h, --help    Show this help.
EOF
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-xcode-simulators only runs on macOS."
  command -v xcrun >/dev/null 2>&1 || die "Xcode command-line tools are not installed."
  command -v pgrep >/dev/null 2>&1 || die "pgrep is not available."
  command -v pkill >/dev/null 2>&1 || die "pkill is not available."
  xcrun --find simctl >/dev/null 2>&1 || die "simctl is not available."

  if (( dry_run )); then
    cat <<'EOF'
Xcode Simulator cleanup preview:
  - Quit the Simulator app if it is running.
  - Shut down every simulator device.
  - Delete devices whose runtimes are unavailable.
  - Erase all apps, data, and settings from every remaining simulator device.
  - Keep available simulator devices and runtimes installed.
EOF
    exit 0
  fi

  quit_simulator

  echo "Shutting down all simulator devices..."
  xcrun simctl shutdown all

  echo "Deleting unavailable simulator devices..."
  xcrun simctl delete unavailable

  echo "Erasing all remaining simulator devices..."
  xcrun simctl erase all
}

main "$@"
