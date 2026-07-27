#!/usr/bin/env bash
set -euo pipefail

COPILOT_CACHE_ROOT="$HOME/.cache/github-copilot"

ALLOWED_TARGETS=(
  "$COPILOT_CACHE_ROOT/project-context"
  "$COPILOT_CACHE_ROOT/project-index"
)

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-copilot-index-cache [--dry-run]

Clear only GitHub Copilot's reconstructable project-context and project-index
caches. Authentication, conversations, sessions, configuration, plugins,
binaries, downloaded runtime packages, and IDE state are preserved.

The cleanup is skipped while Copilot, VS Code, or JetBrains Rider runs.

Options:
  -n, --dry-run Show targeted cache directories and sizes without deleting.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

pattern_is_running() {
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

name_is_running() {
  local process_name="$1"
  local pgrep_status

  if pgrep -x "$process_name" >/dev/null 2>&1; then
    return 0
  else
    pgrep_status=$?
  fi

  (( pgrep_status == 1 )) && return 1
  return 2
}

copilot_is_running() {
  local check_status
  local process_pattern
  local process_name

  for process_pattern in \
    '[/]Visual Studio Code[^/]*[.]app/Contents/' \
    '[/]Rider[.]app/Contents/' \
    '[/]JetBrains Rider[.]app/Contents/'; do
    if pattern_is_running "$process_pattern"; then
      return 0
    else
      check_status=$?
    fi
    (( check_status == 1 )) || return 2
  done

  for process_name in copilot copilot-language-server; do
    if name_is_running "$process_name"; then
      return 0
    else
      check_status=$?
    fi
    (( check_status == 1 )) || return 2
  done

  return 1
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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-copilot-index-cache only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd find
  require_cmd grep
  require_cmd id
  require_cmd pgrep
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$COPILOT_CACHE_ROOT" ]]; then
    echo "GitHub Copilot cache directory does not exist."
    exit 0
  fi
  [[ ! -L "$COPILOT_CACHE_ROOT" ]] || die "Refusing symlinked GitHub Copilot cache directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "GitHub Copilot has no eligible project-context or project-index caches."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'GitHub Copilot project caches: %d directories (reported %.2f GiB)\n' \
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

  if copilot_is_running; then
    echo "Copilot, VS Code, or Rider is running; skipping Copilot project caches."
    exit 0
  else
    process_status=$?
  fi
  (( process_status == 1 )) || die "Could not inspect the Copilot process state."

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if copilot_is_running; then
      echo "A Copilot-related process started during cleanup; leaving remaining caches untouched."
      skipped="$((skipped + ${#TARGETS[@]} - index))"
      break
    else
      process_status=$?
    fi
    (( process_status == 1 )) || die "Could not recheck the Copilot process state."

    if candidate_is_safe "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Copilot deleted: $deleted"
  echo "Copilot skipped: $skipped"
}

main "$@"
