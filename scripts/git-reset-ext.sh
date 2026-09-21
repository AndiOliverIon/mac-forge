#!/usr/bin/env bash
set -euo pipefail

# Usage: git-reset-ext.sh <ext> [<ext> ...]
# For files matching the given extensions under the current directory:
#   - tracked modified/staged files are restored to HEAD (git restore --staged --worktree)
#   - untracked matching files are listed and deleted after a single confirmation
# Extensions are given bare (e.g. `sql json`) and matched case-insensitively.
# Must be run inside a git repository.

# --- Colors (ANSI) ---
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
WHITE=$'\033[97m'
DIM=$'\033[2m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

die() {
  echo "${WHITE}${BOLD}Error:${RESET} $*" >&2
  exit 1
}

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: git-reset-ext <ext> [<ext> ...]

Resets changes for files matching the given extensions, recursively from the
current directory, inside the enclosing git repository.

Examples:
  git-reset-ext sql
  git-reset-ext sql json csproj

Behavior:
  - Tracked modified/staged matches -> restored to HEAD (no prompt).
  - Untracked matches               -> listed, then deleted after one confirm.

Notes:
  - Extensions are given bare and matched case-insensitively.
  - Scope is the directory you run from and its subdirectories.
EOF
  exit 0
fi

# Ensure we're in a git repository
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "Not inside a git repository (or any parent directory)."

REPO_ROOT="$(git rev-parse --show-toplevel)"
CWD="$(pwd -P)"

# Normalize + validate extensions (strip a leading dot, lowercase)
EXTS=()
for raw in "$@"; do
  ext="${raw#.}"
  [[ -n "${ext}" ]] || die "Empty extension argument."
  [[ "${ext}" != *"/"* ]] || die "Invalid extension '${raw}'."
  EXTS+=("$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')")
done

# Does a path match one of the requested extensions (case-insensitive)?
matches_ext() {
  local path="$1"
  local base ext_lower e
  base="${path##*/}"
  [[ "${base}" == *.* ]] || return 1
  ext_lower="$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"
  for e in "${EXTS[@]}"; do
    [[ "${ext_lower}" == "${e}" ]] && return 0
  done
  return 1
}

echo "${BOLD}Extensions${RESET} : ${EXTS[*]}"
echo "${BOLD}Scope${RESET}      : ${CWD}"
echo "${DIM}Repo root  : ${REPO_ROOT}${RESET}"
echo

# Collect tracked (modified/staged) and untracked matches limited to CWD subtree.
# git status --porcelain -z gives NUL-separated entries with repo-root-relative paths.
TRACKED=()     # repo-root-relative paths to restore
UNTRACKED=()   # repo-root-relative paths to delete

while IFS= read -r -d '' entry; do
  status="${entry:0:2}"
  path="${entry:3}"

  # For rename/copy, porcelain -z emits the origin path as an extra NUL field.
  # Consume and ignore it so it isn't misparsed as its own record.
  case "${status}" in
    R*|C*)
      IFS= read -r -d '' _origin || true
      ;;
  esac

  abs="${REPO_ROOT}/${path}"

  # Restrict to current directory subtree.
  [[ "${abs}" == "${CWD}/"* || "${abs}" == "${CWD}" ]] || continue

  matches_ext "${path}" || continue

  if [[ "${status}" == "??" ]]; then
    UNTRACKED+=("${path}")
  else
    TRACKED+=("${path}")
  fi
done < <(cd "${REPO_ROOT}" && git status --porcelain -z --untracked-files=all)

TRACKED_COUNT=${#TRACKED[@]}
UNTRACKED_COUNT=${#UNTRACKED[@]}

if (( TRACKED_COUNT == 0 && UNTRACKED_COUNT == 0 )); then
  echo "${DIM}No changed or untracked files matched. Nothing to do.${RESET}"
  exit 0
fi

# --- Phase 1: restore tracked changes (no prompt) ---
if (( TRACKED_COUNT > 0 )); then
  echo "${ORANGE}${BOLD}Restoring tracked changes (${TRACKED_COUNT}):${RESET}"
  for p in "${TRACKED[@]}"; do
    echo "  ${ORANGE}restore${RESET} ${p}"
  done
  ( cd "${REPO_ROOT}" && git restore --staged --worktree -- "${TRACKED[@]}" )
  echo
fi

# --- Phase 2: delete untracked matches (single confirmation) ---
if (( UNTRACKED_COUNT > 0 )); then
  echo "${YELLOW}${BOLD}Untracked files to DELETE (${UNTRACKED_COUNT}):${RESET}"
  for p in "${UNTRACKED[@]}"; do
    echo "  ${YELLOW}delete${RESET} ${p}"
  done
  echo
  read -r -p "Delete the ${UNTRACKED_COUNT} untracked file(s) above? [y/N]: " CONFIRM
  case "${CONFIRM}" in
    y|Y|yes|YES)
      for p in "${UNTRACKED[@]}"; do
        rm -f -- "${REPO_ROOT}/${p}"
        echo "  ${YELLOW}deleted${RESET} ${p}"
      done
      ;;
    *)
      echo "${DIM}Skipped untracked deletion.${RESET}"
      ;;
  esac
  echo
fi

echo "${GREEN}${BOLD}Done.${RESET}"
