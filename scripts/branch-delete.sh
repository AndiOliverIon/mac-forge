#!/opt/homebrew/bin/bash
set -euo pipefail

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

PATTERN="${1:-}"
if [[ -z "$PATTERN" ]]; then
	die "Usage: $0 <branch-name-fragment>   e.g.  $0 aoi/"
fi

# Ensure we're inside a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	die "This is not a git repository."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# Collect branches matching the pattern
mapfile -t matching_branches < <(
	git for-each-ref --format='%(refname:short)' refs/heads |
		grep --fixed-strings -- "$PATTERN" || true
)

if ((${#matching_branches[@]} == 0)); then
	echo "ℹ No local branches contain '$PATTERN'. Nothing to do."
	exit 0
fi

# Filter out the current branch
to_delete=()
for b in "${matching_branches[@]}"; do
	if [[ "$b" == "$current_branch" ]]; then
		echo "⚠ Skipping current branch: $b"
		continue
	fi
	to_delete+=("$b")
done

if ((${#to_delete[@]} == 0)); then
	echo "ℹ Only matching branch is the current one ('$current_branch'). Nothing to delete."
	exit 0
fi

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
