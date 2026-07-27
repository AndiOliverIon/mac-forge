#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-npm-cache [--dry-run]

Verify npm's configured cache and garbage-collect unneeded cache content.
npm configuration, credentials, global installs, and projects are preserved.

Options:
  -n, --dry-run Show the configured cache location and size without changing it.
  -h, --help    Show this help.
EOF
}

cache_size_kib() {
  local cache_dir="$1"

  if [[ -d "$cache_dir" ]]; then
    du -sk "$cache_dir" | awk '{print $1}'
  else
    echo 0
  fi
}

format_gib() {
  awk -v kib="$1" 'BEGIN { printf "%.2f GiB", kib / 1048576 }'
}

main() {
  local dry_run=0
  local cache_dir
  local before_kib
  local after_kib
  local reclaimed_kib

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-npm-cache only runs on macOS."
  command -v npm >/dev/null 2>&1 || die "npm is not installed."
  command -v awk >/dev/null 2>&1 || die "awk is not available."
  command -v du >/dev/null 2>&1 || die "du is not available."

  cache_dir="$(npm config get cache)"
  [[ -n "$cache_dir" && "$cache_dir" != "undefined" ]] || die "npm did not return a cache path."
  [[ "$cache_dir" == /* ]] || die "npm cache path is not absolute: $cache_dir"

  before_kib="$(cache_size_kib "$cache_dir")"

  if (( dry_run )); then
    echo "npm cache verification preview:"
    echo "  Location: $cache_dir"
    echo "  Reported size: $(format_gib "$before_kib")"
    echo "  Action: npm cache verify"
    exit 0
  fi

  echo "Verifying npm cache: $cache_dir"
  npm cache verify

  after_kib="$(cache_size_kib "$cache_dir")"
  if (( before_kib > after_kib )); then
    reclaimed_kib="$((before_kib - after_kib))"
  else
    reclaimed_kib=0
  fi

  echo "npm cache before: $(format_gib "$before_kib")"
  echo "npm cache after:  $(format_gib "$after_kib")"
  echo "Reclaimed:        $(format_gib "$reclaimed_kib")"
}

main "$@"
