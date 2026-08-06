#!/usr/bin/env bash
set -euo pipefail

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-browser-caches [--dry-run]

Clear Chrome and Brave per-profile disk and code caches. Profiles, accounts,
cookies, sessions, passwords, history, bookmarks, extensions, settings,
downloads, service-worker data, and local storage are kept.

Each browser is skipped independently when it or one of its helpers is running.

Options:
  -n, --dry-run Show targeted cache directories and sizes without deleting.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

browser_is_running() {
  local process_pattern="$1"
  local pgrep_status

  if pgrep -f "$process_pattern" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi

  (( pgrep_status == 1 )) && return 1
  return 2
}

candidate_is_safe() {
  local profiles_root="$1"
  local candidate="$2"
  local uid="$3"
  local relative
  local profile_name

  [[ "$candidate" == "$profiles_root/"* ]] || return 1
  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1

  relative="${candidate#"$profiles_root"/}"
  profile_name="${relative%/*}"
  [[ "$profile_name" != "$relative" && "$profile_name" != */* ]] || return 1

  case "$relative" in
    */Cache | */Code\ Cache)
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1
  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

collect_targets() {
  local profiles_root="$1"
  local uid="$2"
  local candidate
  local size_kib

  TARGETS=()
  TARGET_SIZES_KIB=()

  [[ -d "$profiles_root" && ! -L "$profiles_root" ]] || return

  while IFS= read -r -d '' candidate; do
    if candidate_is_safe "$profiles_root" "$candidate" "$uid"; then
      size_kib="$(du -sk "$candidate" | awk '{print $1}')"
      TARGETS+=("$candidate")
      TARGET_SIZES_KIB+=("$size_kib")
    fi
  done < <(
    find "$profiles_root" -mindepth 2 -maxdepth 2 -type d \
      \( -name Cache -o -name 'Code Cache' \) -print0
  )
}

clean_browser() {
  local browser_name="$1"
  local profiles_root="$2"
  local process_pattern="$3"
  local dry_run="$4"
  local uid="$5"
  local process_status
  local index
  local target
  local total_kib=0
  local deleted=0
  local skipped=0

  if [[ ! -d "$profiles_root" ]]; then
    echo "$browser_name cache directory does not exist."
    return
  fi
  [[ ! -L "$profiles_root" ]] || die "Refusing symlinked $browser_name profile-cache directory."

  collect_targets "$profiles_root" "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "$browser_name has no eligible disk or code caches."
    return
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf '%s disk and code caches: %d directories (reported %.2f GiB)\n' \
    "$browser_name" "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  for index in "${!TARGETS[@]}"; do
    printf '  - %s (%.2f GiB)\n' \
      "${TARGETS[$index]}" \
      "$(awk -v kib="${TARGET_SIZES_KIB[$index]}" 'BEGIN { print kib / 1048576 }')"
  done

  if (( dry_run )); then
    return
  fi

  if browser_is_running "$process_pattern"; then
    echo "$browser_name is running; skipping its caches."
    return
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the $browser_name process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if browser_is_running "$process_pattern"; then
      echo "$browser_name started during cleanup; leaving remaining caches untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the $browser_name process state."

    if candidate_is_safe "$profiles_root" "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "$browser_name deleted: $deleted"
  echo "$browser_name skipped: $skipped"
}

main() {
  local dry_run=0
  local uid
  local chrome_profiles="$HOME/Library/Caches/Google/Chrome"
  local brave_profiles="$HOME/Library/Caches/BraveSoftware/Brave-Browser"

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-browser-caches only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  uid="$(id -u)"

  clean_browser "Chrome" "$chrome_profiles" '[/]Google Chrome[.]app/Contents/' "$dry_run" "$uid"
  echo
  clean_browser "Brave" "$brave_profiles" '[/]Brave Browser[.]app/Contents/' "$dry_run" "$uid"

  if (( dry_run )); then
    echo
    echo "Dry run: nothing was deleted."
  fi
}

main "$@"
