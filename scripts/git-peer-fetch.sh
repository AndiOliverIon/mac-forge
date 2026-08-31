#!/usr/bin/env bash

set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Fetch one committed branch from a peer station and fast-forward the local branch.

Usage:
  git-peer-fetch.sh <hades|masterchief> [branch]

Without a branch argument, an fzf picker lists the peer's available feature
branches. A missing local branch is created without an upstream. Existing
branches are advanced only by fast-forward.

Examples:
  git-peer-fetch.sh masterchief
  git-peer-fetch.sh masterchief aoi/per-1234-feature-dev
  git-peer-fetch.sh hades
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

peer="${1:-}"
requested_branch="${2:-}"

[[ -n "$peer" ]] || {
	usage >&2
	exit 2
}
[[ -z "${3:-}" ]] || die "Too many arguments."

case "$peer" in
	hades | masterchief) ;;
	*) die "Peer must be 'hades' or 'masterchief'." ;;
esac

command -v git >/dev/null 2>&1 || die "Git is required."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
	|| die "Run this command inside a Git worktree."

repo_root="$(git rev-parse --show-toplevel)"
case "$repo_root" in
	"$HOME"/*) repo_relative="${repo_root#"$HOME"/}" ;;
	*) die "Repository must be below your home directory so its peer path can be resolved." ;;
esac

case "$repo_relative" in
	*[[:space:]]* | *:*)
		die "Peer fetch does not support whitespace or ':' in the home-relative repository path."
		;;
esac

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
	die "Working tree is not clean. Commit or otherwise resolve local changes first."
fi

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
peer_user="${FORGE_GIT_PEER_USER:-$(id -un)}"
peer_target="${peer_user}@${peer}"
peer_url="ssh://${peer_target}/~/${repo_relative}"

branch="$requested_branch"
if [[ -z "$branch" ]]; then
	command -v fzf >/dev/null 2>&1 || die "fzf is required when no branch is supplied."

	branch_list="$({
		git ls-remote --heads "$peer_url" \
			|| die "Could not list branches. Verify SSH access and that the peer repository exists."
	} | awk -v current="$current_branch" '
		{
			branch = $2
			sub(/^refs\/heads\//, "", branch)
			if (branch == "main" || branch == "master" || branch == "develop" || branch == "development")
				next
			print (branch == current ? 0 : 1) "\t" branch
	}' | sort -t $'\t' -k1,1n -k2,2 | cut -f2-)"

	[[ -n "$branch_list" ]] || die "No transferable feature branches found on $peer."

	set +e
	branch="$(printf '%s\n' "$branch_list" \
		| fzf --prompt="Branch from ${peer} > " --height=60% --layout=reverse --border)"
	fzf_status=$?
	set -e

	case "$fzf_status" in
		0) ;;
		1 | 130)
			echo "No branch selected."
			exit 0
			;;
		*) die "fzf failed while selecting a branch." ;;
	esac
fi

git check-ref-format --branch "$branch" >/dev/null 2>&1 \
	|| die "Invalid branch name: $branch"

case "$branch" in
	main | master | develop | development)
		die "Protected branch '$branch' cannot be transferred with this command."
		;;
esac

peer_ref="refs/remotes/${peer}/${branch}"

echo "Fetching '$branch' from ${peer}:${repo_relative}..."
git fetch --no-tags "$peer_url" \
	"+refs/heads/${branch}:${peer_ref}" \
	|| die "Fetch failed. Verify SSH access and that the peer repository and branch exist."

if ! git show-ref --verify --quiet "refs/heads/$branch"; then
	git branch --no-track "$branch" "$peer_ref"
	git switch "$branch"
	echo "Created local branch '$branch' at $(git rev-parse --short HEAD) without an upstream."
	exit 0
fi

if [[ "$current_branch" != "$branch" ]]; then
	die "Local branch '$branch' already exists. Switch to it before fetching updates."
fi

local_commit="$(git rev-parse "refs/heads/$branch")"
peer_commit="$(git rev-parse "$peer_ref")"

if [[ "$local_commit" == "$peer_commit" ]]; then
	echo "Already up to date at $(git rev-parse --short "$local_commit")."
	exit 0
fi

if git merge-base --is-ancestor "$local_commit" "$peer_commit"; then
	git merge --ff-only "$peer_ref"
	echo "Fast-forwarded '$branch' to $(git rev-parse --short HEAD)."
	exit 0
fi

if git merge-base --is-ancestor "$peer_commit" "$local_commit"; then
	die "Local '$branch' is ahead of $peer. Fetch this branch in the opposite direction instead."
fi

die "Local '$branch' and $peer have diverged. Resolve the histories manually; nothing was merged."
