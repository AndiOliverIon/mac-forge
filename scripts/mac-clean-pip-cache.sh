#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-pip-cache [--dry-run]

Purge the pip download/wheel cache. Installed packages and virtual environments
are not affected; pip simply re-downloads or rebuilds wheels on the next install.

Options:
  -n, --dry-run Show the cache location and reported size without purging it.
  -h, --help    Show this help.
EOF
}

resolve_pip() {
  if command -v pip3 >/dev/null 2>&1; then
    PIP=(pip3)
  elif command -v pip >/dev/null 2>&1; then
    PIP=(pip)
  elif command -v python3 >/dev/null 2>&1; then
    PIP=(python3 -m pip)
  else
    die "pip is not installed."
  fi
}

main() {
  local dry_run=0
  local cache_dir
  local size

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-pip-cache only runs on macOS."

  local PIP
  resolve_pip

  cache_dir="$("${PIP[@]}" cache dir 2>/dev/null || true)"
  if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
    echo "pip cache directory does not exist."
    exit 0
  fi

  size="$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')"

  if (( dry_run )); then
    echo "pip cache: $cache_dir ($size)"
    echo "Dry run: nothing was purged."
    exit 0
  fi

  echo "Purging pip cache: $cache_dir ($size)..."
  "${PIP[@]}" cache purge
  echo "✓ pip cache purged."
}

main "$@"
