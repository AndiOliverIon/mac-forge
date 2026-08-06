#!/usr/bin/env bash
set -euo pipefail

GENERAL_RETENTION_MINUTES=10080
AI_RETENTION_MINUTES=1440
PREVIEW_LIMIT=25

TARGETS=()
TARGET_TIERS=()
TARGET_RETENTIONS=()
OPEN_PATHS_FILE=""

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-stale-temp [--dry-run]

Delete stale entries owned by the current user from macOS temporary folders.
Recognized AI-tool entries must be older than 24 hours; all other entries must
be older than seven days. Open entries, symlinks, mixed-ownership trees, and
entries containing newer or protected content are preserved.

Options:
  -n, --dry-run Show eligible entries without deleting them.
  -h, --help    Show this help.
EOF
}

cleanup_open_paths_file() {
  if [[ -n "$OPEN_PATHS_FILE" && -f "$OPEN_PATHS_FILE" ]]; then
    rm -f -- "$OPEN_PATHS_FILE"
  fi
}

is_ai_temp_name() {
  local name

  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$name" in
    .com.openai.* | com.openai.* | codex | codex-* | codex_* | .codex-* | \
      claude | claude-* | claude_* | .claude-* | .com.anthropic.* | \
      com.anthropic.* | anthropic-* | github-copilot-* | copilot-* | \
      aider-* | .aider-* | continue-* | .continue-* | cursor-* | \
      .cursor-* | gemini-* | .gemini-*)
      return 0
      ;;
  esac

  return 1
}

candidate_has_open_path() {
  local candidate="$1"

  awk -v target="$candidate" '
    substr($0, 1, 1) == "n" {
      path = substr($0, 2)
      if (path == target || index(path, target "/") == 1) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$OPEN_PATHS_FILE"
}

candidate_has_protected_flags() {
  local candidate="$1"

  find "$candidate" \
    \( -flags +uchg -o -flags +uappnd -o -flags +schg -o \
    -flags +sappnd -o -flags +restricted -o -flags +sunlnk -o \
    -flags +datavault \) \
    -print -quit | grep -q .
}

candidate_is_safe() {
  local root="$1"
  local candidate="$2"
  local retention_minutes="$3"
  local uid="$4"

  [[ "$candidate" == "$root/"* ]] || return 1
  [[ -e "$candidate" ]] || return 1
  [[ ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  if find "$candidate" ! -user "$uid" -print -quit | grep -q .; then
    return 1
  fi

  if find "$candidate" -mmin "-$retention_minutes" -print -quit | grep -q .; then
    return 1
  fi

  if candidate_has_protected_flags "$candidate"; then
    return 1
  fi

  if candidate_has_open_path "$candidate"; then
    return 1
  fi

  return 0
}

scan_open_paths() {
  local root="$1"
  local status

  if lsof -n -P -F n +D "$root" >>"$OPEN_PATHS_FILE" 2>/dev/null; then
    status=0
  else
    status=$?
  fi

  (( status <= 1 )) || die "Could not inspect open files under: $root"
}

collect_targets() {
  local root="$1"
  local uid="$2"
  local candidate
  local name
  local tier
  local retention_minutes

  while IFS= read -r -d '' candidate; do
    name="$(basename "$candidate")"

    if is_ai_temp_name "$name"; then
      tier="AI (24 hours)"
      retention_minutes="$AI_RETENTION_MINUTES"
    else
      tier="general (7 days)"
      retention_minutes="$GENERAL_RETENTION_MINUTES"
    fi

    if candidate_is_safe "$root" "$candidate" "$retention_minutes" "$uid"; then
      TARGETS+=("$candidate")
      TARGET_TIERS+=("$tier")
      TARGET_RETENTIONS+=("$retention_minutes")
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -user "$uid" -print0)
}

print_preview() {
  local count="${#TARGETS[@]}"
  local limit="$count"
  local index
  local remaining

  if (( limit > PREVIEW_LIMIT )); then
    limit="$PREVIEW_LIMIT"
  fi

  for (( index = 0; index < limit; index++ )); do
    printf '  [%s] %s\n' "${TARGET_TIERS[$index]}" "${TARGETS[$index]}"
  done

  remaining="$((count - limit))"
  if (( remaining > 0 )); then
    printf '  ... and %d more eligible entries\n' "$remaining"
  fi
}

main() {
  local dry_run=0
  local uid
  local user_temp
  local normalized_user_temp
  local roots=()
  local root
  local index
  local command_name
  local tier
  local deleted=0
  local skipped=0
  local ai_count=0
  local general_count=0

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

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-stale-temp only runs on macOS."

  for command_name in awk basename find getconf grep id lsof mktemp rm stat tr; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name is not available."
  done

  uid="$(id -u)"
  user_temp="$(getconf DARWIN_USER_TEMP_DIR)"
  [[ -d "$user_temp" ]] || die "User temporary directory does not exist: $user_temp"
  normalized_user_temp="$(cd -- "$user_temp" && pwd -P)"

  case "$normalized_user_temp" in
    /private/var/folders/*/T | /var/folders/*/T)
      ;;
    *)
      die "Unexpected user temporary directory: $normalized_user_temp"
      ;;
  esac

  roots=("/private/tmp")
  if [[ "$normalized_user_temp" != "/private/tmp" ]]; then
    roots+=("$normalized_user_temp")
  fi

  OPEN_PATHS_FILE="$(mktemp -t mac-clean-stale-temp)"
  trap cleanup_open_paths_file EXIT

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || die "Temporary directory does not exist: $root"
    scan_open_paths "$root"
  done

  for root in "${roots[@]}"; do
    collect_targets "$root" "$uid"
  done

  for tier in "${TARGET_TIERS[@]}"; do
    if [[ "$tier" == "AI (24 hours)" ]]; then
      ai_count="$((ai_count + 1))"
    else
      general_count="$((general_count + 1))"
    fi
  done

  echo "Stale temporary cleanup:"
  echo "  AI entries older than 24 hours: $ai_count"
  echo "  Other entries older than 7 days: $general_count"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "Nothing is eligible."
    exit 0
  fi

  print_preview

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  : >"$OPEN_PATHS_FILE"
  for root in "${roots[@]}"; do
    scan_open_paths "$root"
  done

  for index in "${!TARGETS[@]}"; do
    root="/private/tmp"
    if [[ "${TARGETS[$index]}" == "$normalized_user_temp/"* ]]; then
      root="$normalized_user_temp"
    fi

    if candidate_is_safe "$root" "${TARGETS[$index]}" "${TARGET_RETENTIONS[$index]}" "$uid"; then
      rm -rf -- "${TARGETS[$index]}"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Deleted: $deleted"
  echo "Skipped after final safety check: $skipped"
}

main "$@"
