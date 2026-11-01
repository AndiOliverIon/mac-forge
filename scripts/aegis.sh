#!/usr/bin/env bash

set -euo pipefail

station="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
station="$(printf '%s' "$station" | tr '[:upper:]' '[:lower:]')"

workspace_root="${FORGE_UNIVERSE_ROOT:-$HOME/work}"
shared_root=""

case "$station" in
	hades)
		shared_root="/Volumes/shared"
		;;
	masterchief)
		if [[ -z "${FORGE_UNIVERSE_ROOT:-}" ]]; then
			shared_root="$HOME/shared"
		fi
		;;
esac

copilot_args=(
	--allow-all-tools
	--deny-tool='shell(git push)'
	--deny-tool='shell(git send-pack)'
)

if command -v copilot >/dev/null 2>&1; then
	copilot_command=(copilot)
elif command -v gh >/dev/null 2>&1; then
	copilot_command=(gh copilot --)
else
	printf 'Error: GitHub Copilot CLI is unavailable.\n' >&2
	exit 1
fi

for allowed_directory in "$HOME/.config/ai" "$workspace_root" "$shared_root"; do
	[[ -n "$allowed_directory" && -d "$allowed_directory" ]] || continue
	copilot_args+=(--add-dir "$allowed_directory")
done

exec "${copilot_command[@]}" "${copilot_args[@]}" "$@"
