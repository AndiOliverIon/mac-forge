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
require_cmd fzf

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository."

selected_branch="$(
  git for-each-ref --format='%(refname:short)' refs/heads \
    | sort -u \
    | fzf --prompt='Switch branch > ' --height=40% --reverse
)"

if [[ -z "${selected_branch:-}" ]]; then
  echo "No branch selected."
  exit 0
fi

git switch "$selected_branch"
