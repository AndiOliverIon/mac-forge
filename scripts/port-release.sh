#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  port-release.sh <target-base-branch> [--from <source-branch>] [--commit <sha-or-ref>] [--new-branch <name>]

Examples:
  port-release.sh release/2.30
  port-release.sh release/2.30 --from aoi/per-100-my-nice-feature-dev
  port-release.sh release/2.30 --commit a1b2c3d
  port-release.sh release/2.30 --new-branch aoi/per-100-my-nice-feature-230

Behavior:
  1) Resolves commit (default: latest commit from source branch).
  2) Fetches target branch from origin.
  3) Checks out target branch and fast-forwards from origin.
  4) Creates a new branch (suffix derived from target branch, e.g. release/2.30 -> 230).
  5) Cherry-picks the resolved commit.

Notes:
  - Never pushes.
  - Requires clean working tree.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

derive_suffix_from_target() {
  local target="$1"

  if [[ "$target" =~ ^release/([0-9]+)\.([0-9]+)$ ]]; then
    printf "%s%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$target" =~ ^release/([0-9]+)$ ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
    return 0
  fi

  local tail
  tail="${target##*/}"
  tail="${tail//[^[:alnum:]]/}"
  [[ -n "$tail" ]] || tail="target"
  printf "%s" "$tail"
}

build_target_branch_name() {
  local source="$1"
  local suffix="$2"

  if [[ "$source" == *-* ]]; then
    printf "%s-%s" "${source%-*}" "$suffix"
  else
    printf "%s-%s" "$source" "$suffix"
  fi
}

need_cmd git

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this inside a git repository."

[[ -z "$(git status --porcelain)" ]] || die "Working tree is not clean. Commit/stash first."

[[ $# -ge 1 ]] || {
  usage
  exit 1
}

TARGET_BASE=""
SOURCE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
COMMIT_REF=""
NEW_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ -n "${2:-}" ]] || die "Missing value for --from"
      SOURCE_BRANCH="$2"
      shift 2
      ;;
    --commit)
      [[ -n "${2:-}" ]] || die "Missing value for --commit"
      COMMIT_REF="$2"
      shift 2
      ;;
    --new-branch)
      [[ -n "${2:-}" ]] || die "Missing value for --new-branch"
      NEW_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "$TARGET_BASE" ]]; then
        TARGET_BASE="$1"
      else
        die "Unexpected extra argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$TARGET_BASE" ]] || die "Target base branch is required."

git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BASE" || die "Remote branch origin/$TARGET_BASE not found."

if [[ -n "$COMMIT_REF" ]]; then
  COMMIT_SHA="$(git rev-parse --verify "${COMMIT_REF}^{commit}" 2>/dev/null)" || die "Cannot resolve commit from --commit '$COMMIT_REF'."
else
  COMMIT_SHA="$(git rev-parse --verify "${SOURCE_BRANCH}^{commit}" 2>/dev/null)" || die "Cannot resolve source branch '$SOURCE_BRANCH'."
fi

SUFFIX="$(derive_suffix_from_target "$TARGET_BASE")"

if [[ -z "$NEW_BRANCH" ]]; then
  NEW_BRANCH="$(build_target_branch_name "$SOURCE_BRANCH" "$SUFFIX")"
fi

git show-ref --verify --quiet "refs/heads/$NEW_BRANCH" && die "Local branch '$NEW_BRANCH' already exists."
git show-ref --verify --quiet "refs/remotes/origin/$NEW_BRANCH" && die "Remote branch 'origin/$NEW_BRANCH' already exists."

echo "Source branch: $SOURCE_BRANCH"
echo "Commit:        $COMMIT_SHA"
echo "Target base:   $TARGET_BASE"
echo "New branch:    $NEW_BRANCH"
echo
echo "Fetching origin/$TARGET_BASE ..."
git fetch origin "$TARGET_BASE"

if git show-ref --verify --quiet "refs/heads/$TARGET_BASE"; then
  git checkout "$TARGET_BASE"
else
  git checkout -b "$TARGET_BASE" "origin/$TARGET_BASE"
fi

echo "Fast-forwarding $TARGET_BASE from origin/$TARGET_BASE ..."
git merge --ff-only "origin/$TARGET_BASE"

echo "Creating branch $NEW_BRANCH ..."
git checkout -b "$NEW_BRANCH"

echo "Cherry-picking $COMMIT_SHA ..."
if ! git cherry-pick "$COMMIT_SHA"; then
  echo
  echo "Cherry-pick has conflicts."
  echo "Resolve conflicts, then run: git cherry-pick --continue"
  echo "Or abort with: git cherry-pick --abort"
  exit 1
fi

echo
echo "Done. Branch '$NEW_BRANCH' is ready with commit '$COMMIT_SHA'."
