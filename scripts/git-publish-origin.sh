#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd git

REMOTE="origin"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository."
git remote get-url "$REMOTE" >/dev/null 2>&1 || die "Remote '$REMOTE' is not configured."

branch="$(git symbolic-ref --quiet --short HEAD)" || die "Detached HEAD; checkout a local branch first."

set +e
git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$branch" >/dev/null
remote_status=$?
set -e

case "$remote_status" in
  0)
    die "Remote branch '$REMOTE/$branch' already exists. Refusing to push."
    ;;
  2)
    ;;
  *)
    die "Could not check whether '$REMOTE/$branch' exists online."
    ;;
esac

git push -u "$REMOTE" HEAD
