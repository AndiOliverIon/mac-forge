#!/usr/bin/env bash

linux_clean_die() {
  echo "✗ $*" >&2
  exit 1
}

linux_clean_require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || linux_clean_die "This cleaner only runs on Linux."
}

linux_clean_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || linux_clean_die "$1 is not available."
}

linux_clean_parse_dry_run() {
  (( $# <= 1 )) || linux_clean_die "Too many arguments (use --help)"

  case "${1:-}" in
    "")
      LINUX_CLEAN_DRY_RUN=0
      ;;
    -n | --dry-run)
      LINUX_CLEAN_DRY_RUN=1
      ;;
    -h | --help)
      return 2
      ;;
    *)
      linux_clean_die "Unknown argument: $1 (use --help)"
      ;;
  esac
}

linux_clean_format_gib() {
  awk -v kib="$1" 'BEGIN { printf "%.2f GiB", kib / 1048576 }'
}

linux_clean_size_kib() {
  if [[ -e "$1" ]]; then
    du -sk -- "$1" | awk '{print $1}'
  else
    echo 0
  fi
}

linux_clean_process_matches() {
  local pattern="$1"
  local status

  if pgrep -f "$pattern" >/dev/null 2>&1; then
    return 0
  else
    status=$?
  fi

  (( status == 1 )) && return 1
  return 2
}

linux_clean_tree_is_safe() {
  local root="$1"
  local target="$2"
  local uid="$3"

  [[ "$root" == /* && "$target" == "$root/"* ]] || return 1
  [[ -d "$root" && ! -L "$root" ]] || return 1
  [[ -d "$target" && ! -L "$target" ]] || return 1
  [[ "$(stat -c '%u' -- "$root")" == "$uid" ]] || return 1
  [[ "$(stat -c '%u' -- "$target")" == "$uid" ]] || return 1

  if find "$target" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

linux_clean_delete_tree() {
  local root="$1"
  local target="$2"
  local uid="$3"

  linux_clean_tree_is_safe "$root" "$target" "$uid" ||
    linux_clean_die "Target failed its final safety check: $target"
  rm -rf -- "$target"
}
