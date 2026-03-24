#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors (ANSI) ---
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
WHITE=$'\033[97m'
DIM=$'\033[2m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

die() {
  echo "${WHITE}${BOLD}ABORT:${RESET} $*" >&2
  exit 1
}

if [[ -f "${SCRIPT_DIR}/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/forge.sh"
fi

if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "${FORGE_SECRETS_FILE}" ]]; then
  # shellcheck disable=SC1091
  source "${FORGE_SECRETS_FILE}"
fi

remote_url_parts() {
  local url="${1:-}"
  local host=""
  local path=""

  if [[ "${url}" =~ ^git@([^:]+):(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "${url}" =~ ^https?://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "${url}" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  fi

  path="${path%.git}"
  path="${path#/}"

  printf "%s\t%s\n" "${host}" "${path}"
}

detect_provider() {
  local host="${1:-}"

  case "${host}" in
    github.com)
      echo "github"
      ;;
    bitbucket.org)
      echo "bitbucket"
      ;;
    *)
      echo ""
      ;;
  esac
}

github_branch_has_closed_pr() {
  local branch="${1:-}"

  command -v gh >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 1
  [[ -n "${REMOTE_REPO_PATH:-}" ]] || return 1

  gh pr list \
    --repo "${REMOTE_REPO_PATH}" \
    --state closed \
    --head "${branch}" \
    --json headRefName,mergedAt \
    2>/dev/null \
    | jq -e --arg branch "${branch}" 'map(select(.headRefName == $branch and .mergedAt == null)) | length > 0' >/dev/null
}

bitbucket_api_get() {
  local url="${1:-}"

  command -v curl >/dev/null 2>&1 || return 1

  if [[ -n "${BITBUCKET_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${BITBUCKET_TOKEN}" "${url}"
    return 0
  fi

  if [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]]; then
    curl -fsSL -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" "${url}"
    return 0
  fi

  return 1
}

bitbucket_branch_has_declined_pr() {
  local branch="${1:-}"
  local query=""
  local encoded_query=""

  command -v jq >/dev/null 2>&1 || return 1
  [[ -n "${REMOTE_REPO_PATH:-}" ]] || return 1

  query="source.branch.name = \"${branch}\" AND state = \"DECLINED\""
  encoded_query="$(jq -rn --arg q "${query}" '$q|@uri')"

  bitbucket_api_get "https://api.bitbucket.org/2.0/repositories/${REMOTE_REPO_PATH}/pullrequests?q=${encoded_query}&pagelen=1" \
    | jq -e '.values | length > 0' >/dev/null
}

proposal_reason_for_branch() {
  local branch="${1:-}"
  local upstream="${2:-}"
  local track="${3:-}"

  [[ "${upstream}" == "${REMOTE}/"* ]] || return 1

  case "${REMOTE_PROVIDER:-}" in
    github)
      if github_branch_has_closed_pr "${branch}"; then
        echo "GitHub PR closed (not merged)"
        return 0
      fi
      ;;
    bitbucket)
      if bitbucket_branch_has_declined_pr "${branch}"; then
        echo "Bitbucket PR declined"
        return 0
      fi
      ;;
  esac

  return 1
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
  REVIEW (yellow) = local branches that:
    - start with <prefix>
    - have an upstream like ${REMOTE}/...
    - and the hosting provider confirms the PR was closed/declined without merge
  Only SAFE (orange) branches are eligible for deletion.

Colors:
  orange = SAFE to delete (upstream [gone])
  yellow = REVIEW manually (closed/declined PR still on remote)
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
REMOTE_URL="$(git remote get-url "${REMOTE}" 2>/dev/null || true)"
IFS=$'\t' read -r REMOTE_HOST REMOTE_REPO_PATH <<< "$(remote_url_parts "${REMOTE_URL}")"
REMOTE_PROVIDER="$(detect_provider "${REMOTE_HOST}")"

echo "${DIM}Fetching latest from remotes (with prune)...${RESET}"
git fetch --all --prune

# Rows: "<branch>\t<upstream>\t<track>"
mapfile -t ROWS < <(
  git for-each-ref refs/heads \
    --format='%(refname:short)	%(upstream:short)	%(upstream:track)' \
  | awk -v pfx="$PREFIX" '$1 ~ ("^" pfx) { print }'
)

SAFE_TO_DELETE=()        # orange
REVIEW_CANDIDATES=()     # yellow
STILL_ON_REMOTE=()       # white
ORPHAN_NO_UPSTREAM=()    # green

for row in "${ROWS[@]}"; do
  branch="$(printf "%s" "$row" | cut -f1)"
  upstream="$(printf "%s" "$row" | cut -f2)"
  track="$(printf "%s" "$row" | cut -f3)"
  proposal_reason=""

  if [[ -z "${upstream}" ]]; then
    ORPHAN_NO_UPSTREAM+=("${branch}")
    continue
  fi

  if [[ "${upstream}" == "${REMOTE}/"* && "${track}" == "[gone]"* ]]; then
    SAFE_TO_DELETE+=("${branch}")
  elif proposal_reason="$(proposal_reason_for_branch "${branch}" "${upstream}" "${track}")"; then
    REVIEW_CANDIDATES+=("${branch}	${proposal_reason}")
  else
    STILL_ON_REMOTE+=("${branch} -> ${upstream} ${track}")
  fi
done

SAFE_COUNT=${#SAFE_TO_DELETE[@]}
REVIEW_COUNT=${#REVIEW_CANDIDATES[@]}
LOCAL_ONLY_COUNT=${#ORPHAN_NO_UPSTREAM[@]}
KEEP_COUNT=${#STILL_ON_REMOTE[@]}
TOTAL_COUNT=$((SAFE_COUNT + REVIEW_COUNT + LOCAL_ONLY_COUNT + KEEP_COUNT))

print_summary() {
  echo
  echo "${BOLD}Summary for '${PREFIX}':${RESET}"
  echo "------------------------"
  echo "  ${ORANGE}${BOLD}SAFE to delete${RESET} (upstream [gone])     : ${ORANGE}${SAFE_COUNT}${RESET}"
  echo "  ${YELLOW}${BOLD}REVIEW manually${RESET} (closed PR)         : ${YELLOW}${REVIEW_COUNT}${RESET}"
  echo "  ${GREEN}${BOLD}LOCAL-ONLY${RESET} (no upstream)        : ${GREEN}${LOCAL_ONLY_COUNT}${RESET}"
  echo "  ${WHITE}${BOLD}KEEP${RESET} (still on remote)          : ${WHITE}${KEEP_COUNT}${RESET}"
  echo "  ${BOLD}TOTAL${RESET}                           : ${TOTAL_COUNT}"
}

echo
echo "${BOLD}Prefix${RESET} : ${PREFIX}"
echo "${BOLD}Remote${RESET} : ${REMOTE}"
echo "${BOLD}Provider${RESET} : ${REMOTE_PROVIDER:-unknown}"
echo "${BOLD}Mode${RESET}   : $([[ "${MODE}" == "--c" ]] && echo "COMMIT (delete)" || echo "PREVIEW")"

print_summary
echo

echo "${BOLD}Branches matching prefix:${RESET}"
echo "--------------------------------"

echo "${ORANGE}${BOLD}SAFE (orange) — eligible for deletion:${RESET}"
if (( SAFE_COUNT == 0 )); then
  echo "  ${DIM}(none)${RESET}"
else
  for branch in "${SAFE_TO_DELETE[@]}"; do
    echo "  ${ORANGE}${branch}${RESET}"
  done
fi
echo

echo "${YELLOW}${BOLD}REVIEW (yellow) — PR closed/declined, not auto-delete:${RESET}"
if (( REVIEW_COUNT == 0 )); then
  echo "  ${DIM}(none)${RESET}"
else
  for line in "${REVIEW_CANDIDATES[@]}"; do
    branch="$(printf "%s" "${line}" | cut -f1)"
    proposal_reason="$(printf "%s" "${line}" | cut -f2)"
    echo "  ${YELLOW}${branch}${RESET}${DIM}  (${proposal_reason})${RESET}"
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
  branch="${b}"

  [[ -n "${branch}" ]] || die "Empty branch name in candidate list."
  [[ "${branch}" == "${PREFIX}"* ]] || die "Candidate '${branch}' does not start with prefix '${PREFIX}'."

  # Must be a local branch ref
  git show-ref --verify --quiet "refs/heads/${branch}" || die "Candidate '${branch}' is not a local branch (refs/heads)."

  # Never delete current branch
  [[ "${branch}" != "${CURRENT_BRANCH}" ]] || die "Refusing to delete current checked-out branch '${branch}'."

  upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/${branch}")"
  [[ -n "${upstream}" ]] || die "Candidate '${branch}' has no upstream anymore. Refusing to delete."
  [[ "${upstream}" == "${REMOTE}/"* ]] || die "Candidate '${branch}' upstream is '${upstream}', not '${REMOTE}/...'. Refusing."

  track="$(git for-each-ref --format='%(upstream:track)' "refs/heads/${branch}")"
  [[ "${track}" == "[gone]"* ]] || die "Candidate '${branch}' upstream track is '${track}', not [gone]. Refusing."
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
  branch="${b}"

  # Final cheap guard inside the loop
  [[ "${branch}" == "${PREFIX}"* ]] || die "Internal safety check failed: '${branch}' not matching prefix."

  git branch -D "${branch}" >/dev/null
  echo "  ${ORANGE}deleted${RESET} ${branch}"
done

echo
echo "${BOLD}Done.${RESET}"
echo "${DIM}Remaining local branches matching '${PREFIX}':${RESET}"
echo "---------------------------------------------"
git for-each-ref refs/heads --format='%(refname:short)' \
  | grep "^${PREFIX}" || echo "${DIM}(none)${RESET}"
