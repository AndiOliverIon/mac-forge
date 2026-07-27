#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: linux-clean-nuget-transient [--dry-run]

Clear NuGet HTTP, temporary, and plugin caches. Global packages, configuration,
credentials, and projects are preserved.
EOF
}

main() {
  local dry_run=0 cache_type
  local cache_types=(http-cache temp plugins-cache)

  (( $# <= 1 )) || die "Too many arguments (use --help)"
  case "${1:-}" in
    "") ;;
    -n | --dry-run) dry_run=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use --help)" ;;
  esac

  [[ "$(uname -s)" == "Linux" ]] || die "This cleaner only runs on Linux."
  command -v dotnet >/dev/null 2>&1 || { echo ".NET is not installed; skipping."; exit 0; }

  if (( dry_run )); then
    echo "NuGet transient-cache cleanup preview:"
    dotnet nuget locals all --list
    echo "  Preserved: global-packages"
    exit 0
  fi

  for cache_type in "${cache_types[@]}"; do
    echo "Clearing NuGet $cache_type..."
    dotnet nuget locals "$cache_type" --clear
  done
}

main "$@"
