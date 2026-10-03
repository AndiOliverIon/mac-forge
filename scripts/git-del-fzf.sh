#!/opt/homebrew/bin/bash
set -euo pipefail

# Usage: git-del-fzf.sh
# Interactively select (multi-select with fzf) local git branches to delete.
# Must be run inside a git repository.

#######################################
# Optional: load forge config if present
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
fi

#######################################
# Helpers
#######################################
die() {
	echo "✖ $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

#######################################
# Main
#######################################
require_cmd git
require_cmd fzf

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	die "This is not a git repository."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

mapfile -t candidates < <(
	git for-each-ref --format='%(refname:short)' refs/heads |
		grep -vF -- "$current_branch" || true
)

if ((${#candidates[@]} == 0)); then
	echo "ℹ No local branches available to delete (only '$current_branch' exists)."
	exit 0
fi

selection="$(
	printf '%s\n' "${candidates[@]}" |
		fzf --multi \
			--prompt='Delete branches > ' \
			--header='TAB to select multiple, ENTER to confirm selection' \
			--height=60% --layout=reverse --border
)"
fzf_status=$?

case "$fzf_status" in
	0) ;;
	1)
		echo "ℹ No branches selected. Nothing to do."
		exit 0
		;;
	130)
		echo "✋ Aborted."
		exit 0
		;;
	*) die "fzf failed while selecting branches." ;;
esac

if [[ -z "$selection" ]]; then
	echo "ℹ No branches selected. Nothing to do."
	exit 0
fi

mapfile -t to_delete <<<"$selection"

echo "These branches will be deleted (force):"
for b in "${to_delete[@]}"; do
	echo "  - $b"
done

echo
read -r -p "Proceed? [y/N] " answer
case "$answer" in
	[Yy]*)
		for b in "${to_delete[@]}"; do
			echo "🧹 Deleting branch: $b"
			git branch -D "$b"
		done
		echo "✅ Done."
		;;
	*)
		echo "✋ Aborted."
		;;
esac
