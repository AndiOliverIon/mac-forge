#!/usr/bin/env bash
set -euo pipefail

CLAUDE_SUPPORT_ROOT="$HOME/Library/Application Support/Claude"
CLAUDE_APP_PATTERN='[/]Claude[.]app/Contents/'

ALLOWED_TARGETS=(
  "$CLAUDE_SUPPORT_ROOT/Cache"
  "$CLAUDE_SUPPORT_ROOT/Code Cache"
)

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-claude-cache [--dry-run]

Clear only Claude Desktop's browser response and compiled-code caches. Claude
credentials, conversations, sessions, cookies, local storage, configuration,
runtime bundles, binaries, plugins, ~/.claude, and application data are kept.

The cleanup is skipped when Claude Desktop, its helpers, or the Claude CLI runs.

Options:
  -n, --dry-run Show targeted cache directories and sizes without deleting.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

claude_is_running() {
  local pgrep_status

  if pgrep -f "$CLAUDE_APP_PATTERN" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi
  (( pgrep_status == 1 )) || return 2

  if pgrep -x claude >/dev/null 2>&1; then
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-claude-cache only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$CLAUDE_SUPPORT_ROOT" ]]; then
    echo "Claude Desktop support directory does not exist."
    exit 0
  fi
  [[ ! -L "$CLAUDE_SUPPORT_ROOT" ]] || die "Refusing symlinked Claude support directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "Claude has no eligible browser response or code caches."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'Claude browser response and code caches: %d directories (reported %.2f GiB)\n' \
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

  if claude_is_running; then
    echo "Claude is running; skipping its caches."
    exit 0
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the Claude process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if claude_is_running; then
      echo "Claude started during cleanup; leaving remaining caches untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the Claude process state."

    if candidate_is_safe "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Claude deleted: $deleted"
  echo "Claude skipped: $skipped"
}

main "$@"
