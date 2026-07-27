#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-homebrew [--dry-run]

Clean Homebrew using its default cleanup and retention policy.

Options:
  -n, --dry-run Show what Homebrew would remove without changing anything.
  -h, --help    Show this help.
EOF
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-homebrew only runs on macOS."
  command -v brew >/dev/null 2>&1 || die "Homebrew is not installed."

  if (( dry_run )); then
    echo "Homebrew cleanup preview (default policy):"
    brew cleanup --dry-run
  else
    echo "Cleaning Homebrew using its default policy..."
    brew cleanup
  fi
}

main "$@"
