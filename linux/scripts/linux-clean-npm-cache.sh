#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-npm-cache [--dry-run]

Verify npm's configured cache, garbage-collect unneeded content, and delete
npx install directories older than seven days. npm configuration, credentials,
global installs, and projects are preserved.
EOF
}

NPX_RETENTION_DAYS=7

delete_stale_npx() {
  local cache_dir="$1"
  local uid="$2"
  local npx_dir="$cache_dir/_npx"
  local cutoff_epoch candidate candidate_epoch deleted=0

  [[ -d "$npx_dir" && ! -L "$npx_dir" ]] || return 0
  cutoff_epoch="$(( $(date +%s) - NPX_RETENTION_DAYS * 86400 ))"

  while IFS= read -r -d '' candidate; do
    [[ "$candidate" == "$npx_dir/"* && -e "$candidate" && ! -L "$candidate" ]] || continue
    [[ "$(stat -c '%u' -- "$candidate")" == "$uid" ]] || continue
    candidate_epoch="$(stat -c '%Y' -- "$candidate")"
    (( candidate_epoch < cutoff_epoch )) || continue
    if (( LINUX_CLEAN_DRY_RUN )); then
      printf '  - %s\n' "${candidate##*/}"
      deleted="$((deleted + 1))"
      continue
    fi
    rm -rf -- "$candidate"
    deleted="$((deleted + 1))"
  done < <(find "$npx_dir" -mindepth 1 -maxdepth 1 -print0)

  echo "npm _npx entries older than $NPX_RETENTION_DAYS days: $deleted"
}

main() {
  local cache_dir before after reclaimed uid

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  linux_clean_require_cmd npm
  linux_clean_require_cmd awk
  linux_clean_require_cmd date
  linux_clean_require_cmd du
  linux_clean_require_cmd find
  linux_clean_require_cmd id
  linux_clean_require_cmd rm
  linux_clean_require_cmd stat

  cache_dir="$(npm config get cache)"
  [[ "$cache_dir" == /* ]] || linux_clean_die "npm cache path is not absolute: $cache_dir"
  before="$(linux_clean_size_kib "$cache_dir")"
  uid="$(id -u)"
  echo "npm cache: $cache_dir ($(linux_clean_format_gib "$before"))"
  if (( LINUX_CLEAN_DRY_RUN )); then
    echo "Action: npm cache verify"
    echo "Then delete _npx entries older than $NPX_RETENTION_DAYS days:"
    delete_stale_npx "$cache_dir" "$uid"
    exit 0
  fi

  npm cache verify
  delete_stale_npx "$cache_dir" "$uid"
  after="$(linux_clean_size_kib "$cache_dir")"
  (( before > after )) && reclaimed="$((before - after))" || reclaimed=0
  echo "Reclaimed: $(linux_clean_format_gib "$reclaimed")"
}

main "$@"
