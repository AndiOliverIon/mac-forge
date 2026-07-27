#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-nuget-transient [--dry-run]

Clear NuGet HTTP, temporary, and plugin caches. The global packages directory,
NuGet configuration, credentials, and project files are preserved.

Options:
  -n, --dry-run List the targeted cache locations without clearing them.
  -h, --help    Show this help.
EOF
}

CACHE_TYPES=(
  "http-cache"
  "temp"
  "plugins-cache"
)

main() {
  local dry_run=0
  local cache_type

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-nuget-transient only runs on macOS."
  command -v dotnet >/dev/null 2>&1 || die ".NET SDK is not installed."

  if (( dry_run )); then
    echo "NuGet transient-cache cleanup preview:"
    for cache_type in "${CACHE_TYPES[@]}"; do
      dotnet nuget locals "$cache_type" --list --force-english-output
    done
    echo "Global packages are not targeted."
    exit 0
  fi

  for cache_type in "${CACHE_TYPES[@]}"; do
    echo "Clearing NuGet $cache_type..."
    dotnet nuget locals "$cache_type" --clear --force-english-output
  done
}

main "$@"
