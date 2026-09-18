#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-npm-cache [--dry-run]

Verify npm's configured cache, garbage-collect unneeded cache content, and
delete npx install directories older than seven days. npm configuration,
credentials, global installs, projects, and the package download cache that
is still in use are preserved.

Options:
  -n, --dry-run Show the configured cache location and size without changing it.
  -h, --help    Show this help.
EOF
}

NPX_RETENTION_DAYS=7

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

npx_dir_is_safe() {
  local cache_dir="$1"
  local candidate="$2"
  local uid="$3"

  [[ "$candidate" == "$cache_dir/_npx/"* ]] || return 1
  [[ -e "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  return 0
}

delete_stale_npx() {
  local cache_dir="$1"
  local uid="$2"
  local dry_run="$3"
  local npx_dir="$cache_dir/_npx"
  local cutoff_epoch
  local candidate
  local candidate_epoch
  local deleted=0
  local skipped=0

  [[ -d "$npx_dir" && ! -L "$npx_dir" ]] || {
    echo "npm _npx directory does not exist."
    return 0
  }

  cutoff_epoch="$(( $(date +%s) - NPX_RETENTION_DAYS * 86400 ))"

  while IFS= read -r -d '' candidate; do
    npx_dir_is_safe "$cache_dir" "$candidate" "$uid" || continue
    candidate_epoch="$(stat -f '%m' "$candidate")"
    if (( candidate_epoch >= cutoff_epoch )); then
      continue
    fi

    if (( dry_run )); then
      printf '  - %s\n' "$(basename "$candidate")"
      deleted="$((deleted + 1))"
      continue
    fi

    if npx_dir_is_safe "$cache_dir" "$candidate" "$uid"; then
      rm -rf -- "$candidate"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done < <(find "$npx_dir" -mindepth 1 -maxdepth 1 -print0)

  if (( dry_run )); then
    echo "  Stale npx entries older than $NPX_RETENTION_DAYS days: $deleted"
    return 0
  fi

  echo "npm _npx deleted: $deleted"
  echo "npm _npx skipped: $skipped"
}

main() {
  local dry_run=0
  local cache_dir
  local before_kib
  local after_kib
  local reclaimed_kib
  local uid

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
  command -v date >/dev/null 2>&1 || die "date is not available."
  command -v du >/dev/null 2>&1 || die "du is not available."
  command -v find >/dev/null 2>&1 || die "find is not available."
  command -v id >/dev/null 2>&1 || die "id is not available."
  command -v rm >/dev/null 2>&1 || die "rm is not available."
  command -v stat >/dev/null 2>&1 || die "stat is not available."

  cache_dir="$(npm config get cache)"
  [[ -n "$cache_dir" && "$cache_dir" != "undefined" ]] || die "npm did not return a cache path."
  [[ "$cache_dir" == /* ]] || die "npm cache path is not absolute: $cache_dir"

  before_kib="$(cache_size_kib "$cache_dir")"
  uid="$(id -u)"

  if (( dry_run )); then
    echo "npm cache verification preview:"
    echo "  Location: $cache_dir"
    echo "  Reported size: $(format_gib "$before_kib")"
    echo "  Action: npm cache verify"
    echo "  Then delete _npx entries older than $NPX_RETENTION_DAYS days:"
    delete_stale_npx "$cache_dir" "$uid" 1
    exit 0
  fi

  echo "Verifying npm cache: $cache_dir"
  npm cache verify
  delete_stale_npx "$cache_dir" "$uid" 0

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
