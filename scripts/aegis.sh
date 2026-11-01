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

for allowed_directory in "$HOME/.config/ai" "$workspace_root" "$shared_root"; do
	[[ -n "$allowed_directory" && -d "$allowed_directory" ]] || continue
	copilot_args+=(--add-dir "$allowed_directory")
done

exec copilot "${copilot_args[@]}" "$@"
