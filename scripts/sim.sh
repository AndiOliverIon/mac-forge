#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CYCLE_SECONDS="30"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mac-forge"
CONFIG_FILE="$CONFIG_DIR/sim-cycle-seconds"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CYCLER="$SCRIPT_DIR/sim-app-cycle.swift"

usage() {
  cat <<EOF
Usage:
  sim                 Cycle through the apps open when sim starts
  sim --cycle SECONDS Save a new cycle duration and start cycling
  sim --help          Show this help

The default cycle duration is ${DEFAULT_CYCLE_SECONDS} seconds. Press Ctrl+C to stop.
The app collection is captured once at startup. Each activated app receives a brief
mouse movement without clicks; window state and app content are not changed.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

is_valid_cycle() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
    awk -v seconds="$1" 'BEGIN { exit !(seconds > 0) }'
}

cycle_override=""

while (($# > 0)); do
  case "$1" in
    --cycle)
      (($# >= 2)) || die "--cycle requires a number of seconds."
      cycle_override="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1. Run 'sim --help' for usage."
      ;;
  esac
done

if [[ -n "$cycle_override" ]]; then
  is_valid_cycle "$cycle_override" ||
    die "Cycle duration must be a number greater than zero."

  mkdir -p "$CONFIG_DIR"
  printf '%s\n' "$cycle_override" > "$CONFIG_FILE"
  cycle_seconds="$cycle_override"
  echo "Saved cycle duration: ${cycle_seconds} seconds."
elif [[ -f "$CONFIG_FILE" ]]; then
  IFS= read -r cycle_seconds < "$CONFIG_FILE" || true
  is_valid_cycle "${cycle_seconds:-}" ||
    die "Saved cycle duration is invalid. Reset it with 'sim --cycle SECONDS'."
else
  cycle_seconds="$DEFAULT_CYCLE_SECONDS"
fi

[[ "$(uname -s)" == "Darwin" ]] || die "sim only runs on macOS."
command -v swift >/dev/null 2>&1 ||
  die "swift is required. Install the Xcode Command Line Tools with 'xcode-select --install'."
[[ -f "$APP_CYCLER" ]] || die "App cycler not found: $APP_CYCLER"

stop_sim() {
  printf '\nStopped sim.\n'
  exit 130
}

trap stop_sim INT TERM

swift "$APP_CYCLER" "$cycle_seconds"
