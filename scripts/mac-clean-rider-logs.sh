#!/usr/bin/env bash
set -euo pipefail

JETBRAINS_LOG_ROOT="$HOME/Library/Logs/JetBrains"
RIDER_PROCESS_PATTERN='[/]Rider[.]app/Contents/'
RETENTION_DAYS=7

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-rider-logs [--dry-run]

Delete Rider log files older than seven days. Indexes, Local History, settings,
projects, and recent logs are kept. The cleanup is skipped while Rider or one
of its helpers is running.

Options:
  -n, --dry-run Show eligible log files and their size without deleting.
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

candidate_is_safe() {
  local candidate="$1"
  local uid="$2"

  [[ "$candidate" == "$JETBRAINS_LOG_ROOT/Rider"[0-9]*/* ]] || return 1
  [[ -f "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  return 0
}

collect_targets() {
  local uid="$1"
  local cutoff_epoch="$2"
  local candidate
  local candidate_epoch
  local size_kib

  while IFS= read -r -d '' candidate; do
    candidate_is_safe "$candidate" "$uid" || continue
    candidate_epoch="$(stat -f '%m' "$candidate")"
    (( candidate_epoch < cutoff_epoch )) || continue
    size_kib="$(du -sk "$candidate" | awk '{print $1}')"
    TARGETS+=("$candidate")
    TARGET_SIZES_KIB+=("$size_kib")
  done < <(
    find "$JETBRAINS_LOG_ROOT" \
      -mindepth 2 \
      -type f \
      -path "$JETBRAINS_LOG_ROOT/Rider[0-9]*/*" \
      -print0 2>/dev/null
  )
}

main() {
  local dry_run=0
  local uid
  local cutoff_epoch
  local process_status
  local index
  local target
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-rider-logs only runs on macOS."

  require_cmd awk
  require_cmd date
  require_cmd du
  require_cmd find
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$JETBRAINS_LOG_ROOT" ]]; then
    echo "JetBrains log directory does not exist."
    exit 0
  fi
  [[ ! -L "$JETBRAINS_LOG_ROOT" ]] || die "Refusing symlinked JetBrains log directory."

  uid="$(id -u)"
  cutoff_epoch="$(( $(date +%s) - RETENTION_DAYS * 86400 ))"
  collect_targets "$uid" "$cutoff_epoch"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "No Rider log files are older than $RETENTION_DAYS days."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'Rider log files older than %d days: %d (reported %.2f GiB)\n' \
    "$RETENTION_DAYS" "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  if rider_is_running; then
    echo "Rider is running; skipping its logs."
    exit 0
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the Rider process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if rider_is_running; then
      echo "Rider started during cleanup; leaving remaining logs untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the Rider process state."

    if candidate_is_safe "$target" "$uid"; then
      rm -f -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Deleted: $deleted"
  echo "Skipped after final safety check: $skipped"
}

main "$@"
