#!/usr/bin/env bash
set -euo pipefail

CODEX_CACHE_ROOT="$HOME/Library/Caches/Codex"
CODEX_PROCESS_PATTERN='[/]Codex[.]app/Contents/'

ALLOWED_TARGETS=(
  "$CODEX_CACHE_ROOT/Default/Cache"
  "$CODEX_CACHE_ROOT/Default/Code Cache"
  "$CODEX_CACHE_ROOT/Default/Partitions/codex-browser-app/Cache"
  "$CODEX_CACHE_ROOT/Default/Partitions/codex-browser-app/Code Cache"
  "$CODEX_CACHE_ROOT/codex-browser-app/Cache"
  "$CODEX_CACHE_ROOT/codex-browser-app/Code Cache"
)

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-codex-cache [--dry-run]

Clear only Codex desktop's browser response and compiled-code caches. Codex
configuration, credentials, conversations, sessions, projects, worktrees,
application-support data, and ~/.codex are preserved.

The cleanup is skipped when Codex or one of its helpers is running.

Options:
  -n, --dry-run Show targeted cache directories and sizes without deleting.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

codex_is_running() {
  local pgrep_status

  if pgrep -f "$CODEX_PROCESS_PATTERN" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi

  (( pgrep_status == 1 )) && return 1
  return 2
}

is_allowed_target() {
  local candidate="$1"
  local allowed_target

  for allowed_target in "${ALLOWED_TARGETS[@]}"; do
    [[ "$candidate" == "$allowed_target" ]] && return 0
  done

  return 1
}

candidate_is_safe() {
  local candidate="$1"
  local uid="$2"

  is_allowed_target "$candidate" || return 1
  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

collect_targets() {
  local uid="$1"
  local candidate
  local size_kib

  for candidate in "${ALLOWED_TARGETS[@]}"; do
    if candidate_is_safe "$candidate" "$uid"; then
      size_kib="$(du -sk "$candidate" | awk '{print $1}')"
      TARGETS+=("$candidate")
      TARGET_SIZES_KIB+=("$size_kib")
    fi
  done
}

main() {
  local dry_run=0
  local uid
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-codex-cache only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$CODEX_CACHE_ROOT" ]]; then
    echo "Codex desktop cache directory does not exist."
    exit 0
  fi
  [[ ! -L "$CODEX_CACHE_ROOT" ]] || die "Refusing symlinked Codex cache directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "Codex has no eligible browser response or code caches."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'Codex browser response and code caches: %d directories (reported %.2f GiB)\n' \
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

  if codex_is_running; then
    echo "Codex is running; skipping its caches."
    exit 0
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the Codex process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if codex_is_running; then
      echo "Codex started during cleanup; leaving remaining caches untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the Codex process state."

    if candidate_is_safe "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Codex deleted: $deleted"
  echo "Codex skipped: $skipped"
}

main "$@"
