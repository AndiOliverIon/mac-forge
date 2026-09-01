#!/usr/bin/env bash

set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Manage a persistent MasterChief agent session.

Usage:
  masterchief-agent-session.sh <raynor|zeratul> [action] [argument]

Actions:
  open          Attach interactively, creating the session when absent. Default.
  start         Create the detached session when absent and leave it running.
  attach        Attach only when the session already exists.
  shell         Open an independent, nonpersistent shell in the universe.
  status        Show whether the session is running and what its pane is doing.
  logs [lines]  Show recent pane output without attaching. Default: 100 lines.
  stop          Confirm, then terminate the session and everything running in it.
  ensure        Legacy alias for start.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

identity="${1:-}"
action="${2:-open}"
argument="${3:-}"
[[ -z "${4:-}" ]] || die "Too many arguments."

case "$identity" in
	raynor)
		display_name="Raynor"
		universe_root="/home/oliver/raynor"
		;;
	zeratul)
		display_name="Zeratul"
		universe_root="/home/oliver/zeratul"
		;;
	*) die "Identity must be 'raynor' or 'zeratul'." ;;
esac

if [[ "$action" == "-h" || "$action" == "--help" ]]; then
	usage
	exit 0
fi

[[ "$action" != "ensure" ]] || action="start"

case "$action" in
	open | start | attach | shell | status | stop)
		[[ -z "$argument" ]] || die "Action '$action' does not accept an argument."
		;;
	logs)
		log_lines="${argument:-100}"
		[[ "$log_lines" =~ ^[1-9][0-9]*$ ]] || die "Log line count must be a positive integer."
		;;
	*) die "Action must be 'open', 'start', 'attach', 'shell', 'status', 'logs', or 'stop'." ;;
esac

station_name="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
remote_host=""
remote_ssh_options=()

select_remote_host() {
	if [[ -n "${FORGE_MASTERCHIEF_SSH_HOST:-}" ]]; then
		remote_host="$FORGE_MASTERCHIEF_SSH_HOST"
		return
	fi

	remote_host="masterchief"
	remote_ssh_options=(-o BatchMode=yes -o ConnectTimeout=2)
	if ssh "${remote_ssh_options[@]}" \
		-o HostName=masterchief-utp \
		-o HostKeyAlias=masterchief \
		"$remote_host" true </dev/null >/dev/null 2>&1; then
		remote_ssh_options+=(-o HostName=masterchief-utp -o HostKeyAlias=masterchief)
		return
	fi

	if ssh "${remote_ssh_options[@]}" \
		"$remote_host" true </dev/null >/dev/null 2>&1; then
		return
	fi

	die "Cannot connect to MasterChief over UTP or Wi-Fi."
}

if [[ "$station_name" != "masterchief" ]]; then
	command -v ssh >/dev/null 2>&1 || die "ssh is required."
	select_remote_host
	remote_script="/home/oliver/mac-forge/scripts/masterchief-agent-session.sh"
	remote_arguments=("$remote_script" "$identity" "$action")
	[[ "$action" != "logs" ]] || remote_arguments+=("$log_lines")

	case "$action" in
		open | attach | shell | stop) exec ssh "${remote_ssh_options[@]}" -t "$remote_host" "${remote_arguments[@]}" ;;
		*) exec ssh "${remote_ssh_options[@]}" "$remote_host" "${remote_arguments[@]}" ;;
	esac
fi

[[ -d "$universe_root" ]] || die "Universe root not found: $universe_root"

if [[ "$action" == "shell" ]]; then
	command -v zsh >/dev/null 2>&1 || die "zsh is required."
	cd -- "$universe_root"
	export FORGE_AGENT_IDENTITY="$identity"
	export FORGE_UNIVERSE_ROOT="$universe_root"
	export FORGE_WORK_ROOT="$universe_root"
	exec zsh -l
fi

command -v tmux >/dev/null 2>&1 || die "tmux is required."
tmux_command=(tmux -L "$identity")

session_exists() {
	"${tmux_command[@]}" has-session -t "$identity" 2>/dev/null
}

set_session_environment() {
	"${tmux_command[@]}" set-environment -t "$identity" FORGE_AGENT_IDENTITY "$identity"
	"${tmux_command[@]}" set-environment -t "$identity" FORGE_UNIVERSE_ROOT "$universe_root"
	"${tmux_command[@]}" set-environment -t "$identity" FORGE_WORK_ROOT "$universe_root"
}

configure_session() {
	set_session_environment
	"${tmux_command[@]}" set-option -t "$identity" mouse on
	"${tmux_command[@]}" bind-key -T copy-mode WheelUpPane \
		'select-pane; send-keys -X -N 1 scroll-up'
	"${tmux_command[@]}" bind-key -T copy-mode WheelDownPane \
		'select-pane; send-keys -X -N 1 scroll-down'
	"${tmux_command[@]}" bind-key -T copy-mode-vi WheelUpPane \
		'select-pane; send-keys -X -N 1 scroll-up'
	"${tmux_command[@]}" bind-key -T copy-mode-vi WheelDownPane \
		'select-pane; send-keys -X -N 1 scroll-down'
}

start_session() {
	"${tmux_command[@]}" new-session -d \
		-c "$universe_root" \
		-e "FORGE_AGENT_IDENTITY=$identity" \
		-e "FORGE_UNIVERSE_ROOT=$universe_root" \
		-e "FORGE_WORK_ROOT=$universe_root" \
		-s "$identity"
	configure_session
}

case "$action" in
	open)
		if session_exists; then
			configure_session
		else
			start_session
		fi
		exec "${tmux_command[@]}" attach-session -t "$identity"
		;;
	start)
		if session_exists; then
			set_session_environment
			echo "$display_name session is already running."
		else
			start_session
			echo "Started $display_name session at $universe_root."
		fi
		;;
	attach)
		session_exists \
			|| die "$display_name session is not running. Start it with: $identity start"
		configure_session
		exec "${tmux_command[@]}" attach-session -t "$identity"
		;;
	status)
		if ! session_exists; then
			echo "$display_name session: not running."
			exit 1
		fi
		attached="$("${tmux_command[@]}" display-message -p -t "$identity" '#{session_attached}')"
		current_command="$("${tmux_command[@]}" display-message -p -t "$identity:0.0" '#{pane_current_command}')"
		current_path="$("${tmux_command[@]}" display-message -p -t "$identity:0.0" '#{pane_current_path}')"
		created="$("${tmux_command[@]}" display-message -p -t "$identity" '#{session_created}')"
		started="$(date -d "@$created" '+%Y-%m-%d %H:%M:%S')"
		if (( attached > 0 )); then
			connection_state="attached"
		else
			connection_state="detached"
		fi
		printf '%s session: running, %s\n' "$display_name" "$connection_state"
		printf 'Current command: %s\n' "$current_command"
		printf 'Directory: %s\n' "$current_path"
		printf 'Started: %s\n' "$started"
		;;
	logs)
		session_exists \
			|| die "$display_name session is not running. Start it with: $identity start"
		"${tmux_command[@]}" capture-pane -p -t "$identity:0.0" -S "-$log_lines"
		;;
	stop)
		session_exists || {
			echo "$display_name session is not running."
			exit 0
		}
		[[ -t 0 ]] || die "Stopping a session requires an interactive terminal."
		read -r -p "Stop $display_name and terminate everything running in its session? [y/N] " reply
		case "$reply" in
			y | Y | yes | YES | Yes) ;;
			*)
				echo "Stop cancelled."
				exit 0
				;;
		esac
		"${tmux_command[@]}" kill-session -t "$identity"
		echo "Stopped $display_name session."
		;;
esac
