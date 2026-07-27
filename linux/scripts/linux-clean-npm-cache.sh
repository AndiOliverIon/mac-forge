#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-npm-cache [--dry-run]

Verify npm's configured cache and garbage-collect unneeded content. npm
configuration, credentials, global installs, and projects are preserved.
EOF
}

main() {
  local cache_dir before after reclaimed

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  linux_clean_require_cmd npm
  linux_clean_require_cmd awk
  linux_clean_require_cmd du

  cache_dir="$(npm config get cache)"
  [[ "$cache_dir" == /* ]] || linux_clean_die "npm cache path is not absolute: $cache_dir"
  before="$(linux_clean_size_kib "$cache_dir")"
  echo "npm cache: $cache_dir ($(linux_clean_format_gib "$before"))"
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Action: npm cache verify"; exit 0; }

  npm cache verify
  after="$(linux_clean_size_kib "$cache_dir")"
  (( before > after )) && reclaimed="$((before - after))" || reclaimed=0
  echo "Reclaimed: $(linux_clean_format_gib "$reclaimed")"
}

main "$@"
