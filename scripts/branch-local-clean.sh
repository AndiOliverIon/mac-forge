#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"

# --- Colors (ANSI) ---
ORANGE=$'\033[38;5;208m'
GREEN=$'\033[32m'
WHITE=$'\033[97m'
DIM=$'\033[2m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

die() {
  echo "${WHITE}${BOLD}ABORT:${RESET} $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  branch-clean <prefix> [--c]

Examples:
  branch-clean aoi/      # preview only
  branch-clean aoi/ --c  # delete SAFE candidates (orange) after confirmation

Safety model (squash-merge friendly):
  SAFE (orange) = local branches that:
    - start with <prefix>
    - have an upstream like ${REMOTE}/...
    - and upstream tracking state is [gone]
  Only SAFE (orange) branches are eligible for deletion.

Colors:
  orange = SAFE to delete (upstream [gone])
  green  = LOCAL-ONLY (no upstream) - you delete manually if desired
  white  = KEEP (still on remote / not safe by this rule)
EOF
}

# ---------------- Arg parsing ----------------
if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PREFIX="$1"
MODE="${2:-}"   # ONLY allowed value is --c

# Reject any extra args to avoid surprises
if [[ "${3:-}" != "" ]]; then
  die "Too many arguments. Expected: <prefix> [--c]"
fi

# ---- FAIL-CLOSED prefix validation ----
[[ -n "${PREFIX}" ]] || die "Prefix is empty."
[[ "${PREFIX}" != "*" ]] || die "Prefix '*' is not allowed."
(( ${#PREFIX} >= 3 )) || die "Prefix too short. Refusing to run for safety."
# Require a slash to avoid broad prefixes like "f" or "bug"
[[ "${PREFIX}" == */* || "${PREFIX}" == */ ]] || die "Prefix must include '/'. Example: aoi/"
# Disallow whitespace/control characters
[[ "${PREFIX}" != *$'\n'* && "${PREFIX}" != *$'\r'* && "${PREFIX}" != *$'\t'* && "${PREFIX}" != *" "* ]] \
  || die "Prefix contains whitespace/control characters. Refusing."

# ---- Mode validation: delete ONLY with --c ----
if [[ "${MODE}" != "" && "${MODE}" != "--c" ]]; then
  die "Unknown option: ${MODE}. Delete mode is ONLY '--c'."
fi

# ---------------- Preconditions ----------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"
CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"

echo "${DIM}Fetching latest from remotes (with prune)...${RESET}"
git fetch --all --prune

# Rows: "<branch>\t<upstream>\t<track>"
mapfile -t ROWS < <(
  git for-each-ref refs/heads \
    --format='%(refname:short)	%(upstream:short)	%(upstream:track)' \
  | awk -v pfx="$PREFIX" '$1 ~ ("^" pfx) { print }'
)

SAFE_TO_DELETE=()        # orange
STILL_ON_REMOTE=()       # white
ORPHAN_NO_UPSTREAM=()    # green

for row in "${ROWS[@]}"; do
  branch="$(printf "%s" "$row" | cut -f1)"
  upstream="$(printf "%s" "$row" | cut -f2)"
  track="$(printf "%s" "$row" | cut -f3)"

  if [[ -z "${upstream}" ]]; then
    ORPHAN_NO_UPSTREAM+=("${branch}")
    continue
  fi

  if [[ "${upstream}" == "${REMOTE}/"* && "${track}" == "[gone]"* ]]; then
    SAFE_TO_DELETE+=("${branch}")
  else
    STILL_ON_REMOTE+=("${branch} -> ${upstream} ${track}")
  fi
done

SAFE_COUNT=${#SAFE_TO_DELETE[@]}
LOCAL_ONLY_COUNT=${#ORPHAN_NO_UPSTREAM[@]}
KEEP_COUNT=${#STILL_ON_REMOTE[@]}
TOTAL_COUNT=$((SAFE_COUNT + LOCAL_ONLY_COUNT + KEEP_COUNT))

print_summary() {
  echo
  echo "${BOLD}Summary for '${PREFIX}':${RESET}"
  echo "------------------------"
  echo "  ${ORANGE}${BOLD}SAFE to delete${RESET} (upstream [gone]) : ${ORANGE}${SAFE_COUNT}${RESET}"
  echo "  ${GREEN}${BOLD}LOCAL-ONLY${RESET} (no upstream)        : ${GREEN}${LOCAL_ONLY_COUNT}${RESET}"
  echo "  ${WHITE}${BOLD}KEEP${RESET} (still on remote)          : ${WHITE}${KEEP_COUNT}${RESET}"
  echo "  ${BOLD}TOTAL${RESET}                           : ${TOTAL_COUNT}"
}

echo
echo "${BOLD}Prefix${RESET} : ${PREFIX}"
echo "${BOLD}Remote${RESET} : ${REMOTE}"
echo "${BOLD}Mode${RESET}   : $([[ "${MODE}" == "--c" ]] && echo "COMMIT (delete)" || echo "PREVIEW")"

print_summary
echo

echo "${BOLD}Branches matching prefix:${RESET}"
echo "--------------------------------"

echo "${ORANGE}${BOLD}SAFE (orange) — eligible for deletion:${RESET}"
if (( SAFE_COUNT == 0 )); then
  echo "  ${DIM}(none)${RESET}"
else
  for b in "${SAFE_TO_DELETE[@]}"; do
    echo "  ${ORANGE}${b}${RESET}"
  done
fi
echo

echo "${GREEN}${BOLD}LOCAL-ONLY (green) — no upstream set:${RESET}"
if (( LOCAL_ONLY_COUNT == 0 )); then
  echo "  ${DIM}(none)${RESET}"
else
  for b in "${ORPHAN_NO_UPSTREAM[@]}"; do
    echo "  ${GREEN}${b}${RESET}"
  done
fi
echo

echo "${WHITE}${BOLD}KEEP (white) — still on remote / not safe:${RESET}"
if (( KEEP_COUNT == 0 )); then
  echo "  ${DIM}(none)${RESET}"
else
  for line in "${STILL_ON_REMOTE[@]}"; do
    echo "  ${WHITE}${line}${RESET}"
  done
fi

# Preview mode ends here
if [[ "${MODE}" != "--c" ]]; then
  echo
  print_summary
  echo "${DIM}Preview only — nothing deleted.${RESET}"
  exit 0
fi

# ---------------- BULLETPROOF deletion gate ----------------
echo
echo "${DIM}Preparing to delete SAFE (orange) branches only...${RESET}"

# If nothing to delete, stop safely
if (( SAFE_COUNT == 0 )); then
  echo "${DIM}No SAFE branches found. Nothing to delete.${RESET}"
  exit 0
fi

# Ensure unique list (abort on duplicates)
dup_count="$(printf "%s\n" "${SAFE_TO_DELETE[@]}" | sort | uniq -d | wc -l | tr -d ' ')"
[[ "${dup_count}" == "0" ]] || die "Duplicate branches detected in candidate list. Refusing to delete."

# Re-validate each candidate from git itself right before deleting.
# If ANY candidate fails -> abort ALL deletions.
for b in "${SAFE_TO_DELETE[@]}"; do
  [[ -n "${b}" ]] || die "Empty branch name in candidate list."
  [[ "${b}" == "${PREFIX}"* ]] || die "Candidate '${b}' does not start with prefix '${PREFIX}'."

  # Must be a local branch ref
  git show-ref --verify --quiet "refs/heads/${b}" || die "Candidate '${b}' is not a local branch (refs/heads)."

  # Never delete current branch
  [[ "${b}" != "${CURRENT_BRANCH}" ]] || die "Refusing to delete current checked-out branch '${b}'."

  # Must still have upstream and it must be origin/*
  upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/${b}")"
  [[ -n "${upstream}" ]] || die "Candidate '${b}' has no upstream anymore. Refusing to delete."
  [[ "${upstream}" == "${REMOTE}/"* ]] || die "Candidate '${b}' upstream is '${upstream}', not '${REMOTE}/...'. Refusing."

  # Must still be marked [gone] right now
  track="$(git for-each-ref --format='%(upstream:track)' "refs/heads/${b}")"
  [[ "${track}" == "[gone]"* ]] || die "Candidate '${b}' upstream track is '${track}', not [gone]. Refusing."
done

# Extra human confirmation to prevent fat-finger mistakes
echo
echo "${WHITE}${BOLD}DELETE CONFIRMATION REQUIRED${RESET}"
echo "${DIM}This will FORCE-delete (${BOLD}git branch -D${RESET}${DIM}) exactly ${SAFE_COUNT} branch(es), all starting with:${RESET} ${BOLD}${PREFIX}${RESET}"
echo "${DIM}Type the prefix exactly to continue, or anything else to abort.${RESET}"
read -r -p "Confirm prefix: " CONFIRM

[[ "${CONFIRM}" == "${PREFIX}" ]] || die "Confirmation did not match prefix. Nothing deleted."

echo
echo "${ORANGE}${BOLD}Deleting SAFE (orange) branches with: git branch -D${RESET}"
echo "---------------------------------------------------------"

for b in "${SAFE_TO_DELETE[@]}"; do
  # Final cheap guard inside the loop
  [[ "${b}" == "${PREFIX}"* ]] || die "Internal safety check failed: '${b}' not matching prefix."

  git branch -D "${b}" >/dev/null
  echo "  ${ORANGE}deleted${RESET} ${b}"
done

echo
echo "${BOLD}Done.${RESET}"
echo "${DIM}Remaining local branches matching '${PREFIX}':${RESET}"
echo "---------------------------------------------"
git for-each-ref refs/heads --format='%(refname:short)' \
  | grep "^${PREFIX}" || echo "${DIM}(none)${RESET}"
