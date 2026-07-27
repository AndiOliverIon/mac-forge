#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean [--full | --list]

Run the approved standard macOS cleanup scripts in order.

Options:
  --full     Run standard and full-only cleanup scripts.
  --list     Show all approved cleanup scripts and their classification.
  -h, --help Show this help.
EOF
}

# Add a child script here only after its behavior has been reviewed and approved.
STANDARD_CLEANERS=(
  "$SCRIPT_DIR/mac-clean-homebrew.sh"
  "$SCRIPT_DIR/mac-clean-browser-caches.sh"
  "$SCRIPT_DIR/mac-clean-claude-cache.sh"
  "$SCRIPT_DIR/mac-clean-codex-cache.sh"
  "$SCRIPT_DIR/mac-clean-copilot-index-cache.sh"
  "$SCRIPT_DIR/mac-clean-docker-build-cache.sh"
  "$SCRIPT_DIR/mac-clean-nuget-transient.sh"
  "$SCRIPT_DIR/mac-clean-npm-cache.sh"
  "$SCRIPT_DIR/mac-clean-rider-caches.sh"
  "$SCRIPT_DIR/mac-clean-yarn-cache.sh"
  "$SCRIPT_DIR/mac-clean-swiftpm-cache.sh"
  "$SCRIPT_DIR/mac-clean-stale-temp.sh"
  "$SCRIPT_DIR/mac-clean-xcode-derived-data.sh"
  "$SCRIPT_DIR/mac-clean-xcode-simulators.sh"
  "$SCRIPT_DIR/mac-clean-xcode-test-clones.sh"
)

FULL_CLEANERS=(
)

list_cleaners() {
  local cleaner

  echo "Standard:"
  if (( ${#STANDARD_CLEANERS[@]} == 0 )); then
    echo "  (none)"
  else
    for cleaner in "${STANDARD_CLEANERS[@]}"; do
      printf '  - %s\n' "$(basename "$cleaner")"
    done
  fi

  echo "Full-only:"
  if (( ${#FULL_CLEANERS[@]} == 0 )); then
    echo "  (none)"
  else
    for cleaner in "${FULL_CLEANERS[@]}"; do
      printf '  - %s\n' "$(basename "$cleaner")"
    done
  fi
}

main() {
  local mode="standard"
  local cleaner
  local cleaner_name
  local index
  local status
  local cleaners=()

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean only runs on macOS."
  (( $# <= 1 )) || die "Too many arguments (use --help)"

  case "${1:-}" in
    "")
      ;;
    --full)
      mode="full"
      ;;
    --list)
      list_cleaners
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac

  if (( ${#STANDARD_CLEANERS[@]} > 0 )); then
    cleaners=("${STANDARD_CLEANERS[@]}")
  fi
  if [[ "$mode" == "full" ]] && (( ${#FULL_CLEANERS[@]} > 0 )); then
    cleaners+=("${FULL_CLEANERS[@]}")
  fi

  if (( ${#cleaners[@]} == 0 )); then
    echo "No macOS cleanup items have been approved yet."
    exit 0
  fi

  for cleaner in "${cleaners[@]}"; do
    [[ "$cleaner" == "$SCRIPT_DIR/"* ]] || die "Cleaner is outside the scripts directory: $cleaner"
    [[ -f "$cleaner" ]] || die "Cleaner does not exist: $cleaner"
    [[ -x "$cleaner" ]] || die "Cleaner is not executable: $cleaner"
  done

  echo "mac-clean ($mode): ${#cleaners[@]} approved item(s)"

  for index in "${!cleaners[@]}"; do
    cleaner="${cleaners[$index]}"
    cleaner_name="$(basename "$cleaner")"

    echo
    printf '[%d/%d] %s\n' "$((index + 1))" "${#cleaners[@]}" "$cleaner_name"

    if "$cleaner"; then
      echo "✓ Completed: $cleaner_name"
    else
      status=$?
      echo "✗ Failed: $cleaner_name (exit $status). Stopping." >&2
      exit "$status"
    fi
  done

  echo
  echo "mac-clean completed."
}

main "$@"
