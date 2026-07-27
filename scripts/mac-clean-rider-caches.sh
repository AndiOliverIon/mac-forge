#!/usr/bin/env bash
set -euo pipefail

JETBRAINS_CACHE_ROOT="$HOME/Library/Caches/JetBrains"
RIDER_PROCESS_PATTERN='[/]Rider[.]app/Contents/'

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-rider-caches [--dry-run]

Clear only Rider's reconstructable index, IDE cache, and ReSharper cache
directories for installed Rider versions. Local History, file/test history,
plugins, settings, credentials, projects, VCS data, and JCEF data are kept.

The cleanup is skipped when Rider or one of its backend/helper processes runs.

Options:
  -n, --dry-run Show targeted cache directories and sizes without deleting.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

rider_is_running() {
  local pgrep_status

  if pgrep -f "$RIDER_PROCESS_PATTERN" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi

  (( pgrep_status == 1 )) && return 1
  return 2
}

rider_root_is_safe() {
  local rider_root="$1"
  local rider_name

  [[ "$rider_root" == "$JETBRAINS_CACHE_ROOT/"* ]] || return 1
  [[ -d "$rider_root" && ! -L "$rider_root" ]] || return 1

  rider_name="${rider_root#"$JETBRAINS_CACHE_ROOT"/}"
  [[ "$rider_name" != */* ]] || return 1

  case "$rider_name" in
    Rider[0-9]*)
      return 0
      ;;
  esac

  return 1
}

candidate_is_safe() {
  local rider_root="$1"
  local candidate="$2"
  local uid="$3"

  rider_root_is_safe "$rider_root" || return 1

  case "$candidate" in
    "$rider_root/index" | "$rider_root/caches" | "$rider_root/resharper-host")
      ;;
    *)
      return 1
      ;;
  esac

  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

collect_targets() {
  local uid="$1"
  local rider_root
  local candidate
  local cache_name
  local size_kib

  while IFS= read -r -d '' rider_root; do
    rider_root_is_safe "$rider_root" || continue

    for cache_name in index caches resharper-host; do
      candidate="$rider_root/$cache_name"
      if candidate_is_safe "$rider_root" "$candidate" "$uid"; then
        size_kib="$(du -sk "$candidate" | awk '{print $1}')"
        TARGETS+=("$candidate")
        TARGET_SIZES_KIB+=("$size_kib")
      fi
    done
  done < <(
    find "$JETBRAINS_CACHE_ROOT" -mindepth 1 -maxdepth 1 \
      -type d -name 'Rider[0-9]*' -print0
  )
}

main() {
  local dry_run=0
  local uid
  local process_status
  local index
  local target
  local rider_root
  local total_kib=0
  local deleted=0
  local skipped=0

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-rider-caches only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$JETBRAINS_CACHE_ROOT" ]]; then
    echo "JetBrains cache directory does not exist."
    exit 0
  fi
  [[ ! -L "$JETBRAINS_CACHE_ROOT" ]] || die "Refusing symlinked JetBrains cache directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "Rider has no eligible index, IDE cache, or ReSharper cache directories."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'Rider reconstructable caches: %d directories (reported %.2f GiB)\n' \
    "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  for index in "${!TARGETS[@]}"; do
    printf '  - %s (%.2f GiB)\n' \
      "${TARGETS[$index]}" \
      "$(awk -v kib="${TARGET_SIZES_KIB[$index]}" 'BEGIN { print kib / 1048576 }')"
  done

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  if rider_is_running; then
    echo "Rider is running; skipping its caches."
    exit 0
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the Rider process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"
    rider_root="${target%/*}"

    if rider_is_running; then
      echo "Rider started during cleanup; leaving remaining caches untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the Rider process state."

    if candidate_is_safe "$rider_root" "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Rider deleted: $deleted"
  echo "Rider skipped: $skipped"
}

main "$@"
