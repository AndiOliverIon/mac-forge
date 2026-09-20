#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

RETENTION_MINUTES=10080
AI_RETENTION_MINUTES=1440
HANDOFF_RETENTION_MINUTES=4320

HANDOFF_ROOTS=(
  "$HOME/work/.ai/review-handoff"
  "$HOME/zeratul/.ai/review-handoff"
  "$HOME/raynor/.ai/review-handoff"
)

usage() {
  cat <<'EOF'
Usage: linux-clean-stale-temp [--dry-run]

Delete current-user /tmp entries whose entire trees are older than seven days.
Recognized AI-tool entries may be deleted after 24 hours. Open entries,
symlinks, mixed-ownership trees, and entries with newer content are preserved.

Also removes handoff review files (request*/findings* markdown) in the work,
zeratul, and raynor review-handoff lanes that are older than three days.
EOF
}

is_ai_name() {
  local name="${1,,}"
  case "$name" in
    .agents | .codex | codex* | claude* | github-copilot* | copilot*) return 0 ;;
  esac
  return 1
}

candidate_is_safe() {
  local target="$1" uid="$2" retention="$3"
  local lsof_status

  [[ "$target" == /tmp/* && -e "$target" && ! -L "$target" ]] || return 1
  [[ "$(stat -c '%u' -- "$target")" == "$uid" ]] || return 1
  if find "$target" ! -user "$uid" -print -quit | grep -q .; then return 1; fi
  if find "$target" -mmin "-$retention" -print -quit | grep -q .; then return 1; fi
  if [[ -d "$target" ]]; then
    if lsof -n -P +D "$target" >/dev/null 2>&1; then
      return 1
    else
      lsof_status=$?
    fi
  else
    if lsof -n -P -- "$target" >/dev/null 2>&1; then
      return 1
    else
      lsof_status=$?
    fi
  fi
  (( lsof_status == 1 )) || return 1
  return 0
}

handoff_candidate_is_safe() {
  local file="$1" uid="$2"

  [[ -f "$file" && ! -L "$file" ]] || return 1
  [[ "$(stat -c '%u' -- "$file")" == "$uid" ]] || return 1
  find "$file" -maxdepth 0 -mmin "+$HANDOFF_RETENTION_MINUTES" -print -quit | grep -q .
}

main() {
  local uid target name retention size total=0
  local targets=()
  local handoff_targets=() root file

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id lsof rm stat; do
    linux_clean_require_cmd "$command"
  done
  [[ ! -L /tmp ]] || linux_clean_die "Refusing symlinked /tmp."
  uid="$(id -u)"

  while IFS= read -r -d '' target; do
    name="${target##*/}"
    retention="$RETENTION_MINUTES"
    is_ai_name "$name" && retention="$AI_RETENTION_MINUTES"
    candidate_is_safe "$target" "$uid" "$retention" || continue
    targets+=("$target")
    size="$(linux_clean_size_kib "$target")"
    total="$((total + size))"
  done < <(find /tmp -mindepth 1 -maxdepth 1 -user "$uid" -print0)

  for root in "${HANDOFF_ROOTS[@]}"; do
    [[ -d "$root" && ! -L "$root" ]] || continue
    while IFS= read -r -d '' file; do
      handoff_candidate_is_safe "$file" "$uid" || continue
      handoff_targets+=("$file")
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type f -user "$uid" \
      \( -name 'request-*.md' -o -name 'request.md' \
      -o -name 'findings-*.md' -o -name 'findings.md' \) \
      -mmin "+$HANDOFF_RETENTION_MINUTES" -print0 2>/dev/null)
  done

  echo "Eligible stale temporary entries: ${#targets[@]} ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do echo "  - $target"; done
  echo "Eligible handoff review files older than 3 days: ${#handoff_targets[@]}"
  for file in "${handoff_targets[@]}"; do echo "  - $file"; done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }

  for target in "${targets[@]}"; do
    name="${target##*/}"
    retention="$RETENTION_MINUTES"
    is_ai_name "$name" && retention="$AI_RETENTION_MINUTES"
    candidate_is_safe "$target" "$uid" "$retention" ||
      linux_clean_die "Temporary target failed its final safety check: $target"
    rm -rf -- "$target"
  done
  for file in "${handoff_targets[@]}"; do
    handoff_candidate_is_safe "$file" "$uid" ||
      linux_clean_die "Handoff review file failed its final safety check: $file"
    rm -f -- "$file"
  done
  echo "Temporary entries deleted: ${#targets[@]}"
  echo "Handoff review files deleted: ${#handoff_targets[@]}"
}

main "$@"
