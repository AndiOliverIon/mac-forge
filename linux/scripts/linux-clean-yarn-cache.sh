#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-yarn-cache [--dry-run]

Clear Yarn v1's downloaded package cache. Projects, node_modules, lockfiles,
global packages, configuration, and credentials are preserved.
EOF
}

main() {
  local version cache_root="$HOME/.cache/yarn" cache_dir before status

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  linux_clean_require_cmd yarn
  linux_clean_require_cmd pgrep

  version="$(yarn --version)"
  [[ "$version" == 1.* ]] || linux_clean_die "Expected Yarn v1, found: $version"
  cache_dir="$(yarn --cache-folder "$cache_root" cache dir)"
  [[ "$cache_dir" == "$cache_root/"* ]] || linux_clean_die "Unexpected Yarn cache path: $cache_dir"
  before="$(linux_clean_size_kib "$cache_dir")"
  echo "Yarn v1 cache: $cache_dir ($(linux_clean_format_gib "$before"))"
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Action: yarn cache clean"; exit 0; }

  if linux_clean_process_matches '(^|/)(yarn|yarnpkg)([[:space:]]|$)'; then
    echo "Yarn is running; skipping its cache."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect Yarn process state."
  yarn --cache-folder "$cache_root" cache clean
}

main "$@"
