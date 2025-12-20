#!/usr/bin/env bash
set -euo pipefail

# Usage: git-del.sh <keyword>
# Deletes *local* branches whose names contain <keyword>.
# Must be run inside a git repository.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <keyword>" >&2
  exit 1
fi

KEYWORD="$1"

# Ensure we're in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not a git repository (or any of the parent directories)." >&2
  exit 1
fi

# Get current branch to avoid deleting it
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Find matching local branches (excluding HEAD, and filtering by keyword)
mapfile -t MATCHING_BRANCHES < <(
  git branch --format='%(refname:short)' \
  | grep -F "$KEYWORD" \
  | grep -vE "^\s*(${CURRENT_BRANCH})\s*$" \
  || true
)

if [[ ${#MATCHING_BRANCHES[@]} -eq 0 ]]; then
  echo "No local branches found matching keyword '$KEYWORD' (excluding current branch '$CURRENT_BRANCH')."
  exit 0
fi

echo "The following local branches will be deleted (excluding current branch '$CURRENT_BRANCH'):"
for b in "${MATCHING_BRANCHES[@]}"; do
  echo "  $b"
done

read -r -p "Proceed with deletion? [y/N]: " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES)
    ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

# Delete branches
for b in "${MATCHING_BRANCHES[@]}"; do
  echo "Deleting branch: $b"
  git branch -D "$b"
done

echo "Done."
