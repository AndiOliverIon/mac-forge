#!/usr/bin/env bash

set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Attach to or create a persistent MasterChief agent session.

Usage:
  masterchief-agent-session.sh <raynor|zeratul> [attach|ensure]

Actions:
  attach  Attach interactively, creating the session when absent. Default.
  ensure  Create the detached session when absent and leave it running.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

identity="${1:-}"
action="${2:-attach}"
[[ -z "${3:-}" ]] || die "Too many arguments."

case "$identity" in
	raynor) universe_root="/home/oliver/raynor" ;;
	zeratul) universe_root="/home/oliver/zeratul" ;;
	*) die "Identity must be 'raynor' or 'zeratul'." ;;
esac

case "$action" in
	attach | ensure) ;;
	*) die "Action must be 'attach' or 'ensure'." ;;
esac

station_name="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
remote_host="${FORGE_MASTERCHIEF_SSH_HOST:-oliver@masterchief}"

if [[ "$station_name" == "masterchief" ]]; then
	command -v tmux >/dev/null 2>&1 || die "tmux is required."
	[[ -d "$universe_root" ]] || die "Universe root not found: $universe_root"

	if tmux -L "$identity" has-session -t "$identity" 2>/dev/null; then
		created=0
	else
		tmux -L "$identity" new-session -d \
			-e "FORGE_AGENT_IDENTITY=$identity" \
			-e "FORGE_UNIVERSE_ROOT=$universe_root" \
			-e "FORGE_WORK_ROOT=$universe_root" \
			-s "$identity"
		tmux -L "$identity" send-keys -l -t "$identity:0.0" "cd -- $universe_root"
		tmux -L "$identity" send-keys -t "$identity:0.0" C-m
		created=1
	fi
	tmux -L "$identity" set-environment -t "$identity" FORGE_AGENT_IDENTITY "$identity"
	tmux -L "$identity" set-environment -t "$identity" FORGE_UNIVERSE_ROOT "$universe_root"
	tmux -L "$identity" set-environment -t "$identity" FORGE_WORK_ROOT "$universe_root"

	if [[ "$action" == "ensure" ]]; then
		if [[ "$created" -eq 1 ]]; then
			echo "Started session '$identity' at $universe_root."
		else
			echo "Session '$identity' is already running."
		fi
		exit 0
	fi

	exec tmux -L "$identity" attach-session -t "$identity"
fi

command -v ssh >/dev/null 2>&1 || die "ssh is required."

if [[ "$action" == "ensure" ]]; then
	exec ssh "$remote_host" \
		"test -d '$universe_root' && { /usr/bin/tmux -L '$identity' has-session -t '$identity' 2>/dev/null || { /usr/bin/tmux -L '$identity' new-session -d -e 'FORGE_AGENT_IDENTITY=$identity' -e 'FORGE_UNIVERSE_ROOT=$universe_root' -e 'FORGE_WORK_ROOT=$universe_root' -s '$identity'; /usr/bin/tmux -L '$identity' send-keys -l -t '$identity:0.0' 'cd -- $universe_root'; /usr/bin/tmux -L '$identity' send-keys -t '$identity:0.0' C-m; }; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_AGENT_IDENTITY '$identity'; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_UNIVERSE_ROOT '$universe_root'; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_WORK_ROOT '$universe_root'; }"
fi

exec ssh -t "$remote_host" \
	"test -d '$universe_root' && { /usr/bin/tmux -L '$identity' has-session -t '$identity' 2>/dev/null || { /usr/bin/tmux -L '$identity' new-session -d -e 'FORGE_AGENT_IDENTITY=$identity' -e 'FORGE_UNIVERSE_ROOT=$universe_root' -e 'FORGE_WORK_ROOT=$universe_root' -s '$identity'; /usr/bin/tmux -L '$identity' send-keys -l -t '$identity:0.0' 'cd -- $universe_root'; /usr/bin/tmux -L '$identity' send-keys -t '$identity:0.0' C-m; }; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_AGENT_IDENTITY '$identity'; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_UNIVERSE_ROOT '$universe_root'; /usr/bin/tmux -L '$identity' set-environment -t '$identity' FORGE_WORK_ROOT '$universe_root'; } && exec /usr/bin/tmux -L '$identity' attach-session -t '$identity'"
