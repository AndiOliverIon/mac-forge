if [[ -n "${FORGE_AGENT_IDENTITY:-}" ]]; then
	case "$FORGE_AGENT_IDENTITY" in
		raynor) expected_universe_root="/home/oliver/raynor" ;;
		zeratul) expected_universe_root="/home/oliver/zeratul" ;;
		*)
			print -u2 "Unknown Forge agent identity: $FORGE_AGENT_IDENTITY"
			unset FORGE_AGENT_IDENTITY FORGE_UNIVERSE_ROOT FORGE_WORK_ROOT
			return
			;;
	esac

	if [[ "${FORGE_UNIVERSE_ROOT:-}" != "$expected_universe_root" ]]; then
		print -u2 "Invalid universe root for $FORGE_AGENT_IDENTITY: ${FORGE_UNIVERSE_ROOT:-unset}"
		unset FORGE_AGENT_IDENTITY FORGE_UNIVERSE_ROOT FORGE_WORK_ROOT
		return
	fi

	export FORGE_WORK_ROOT="$FORGE_UNIVERSE_ROOT"

	_forge_agent_universe_guard() {
		case "$PWD" in
			"$FORGE_UNIVERSE_ROOT" | "$FORGE_UNIVERSE_ROOT"/*) ;;
			*)
				print -u2 "Blocked: $FORGE_AGENT_IDENTITY must remain inside $FORGE_UNIVERSE_ROOT"
				builtin cd -- "$FORGE_UNIVERSE_ROOT"
				return 1
				;;
		esac
	}

	autoload -Uz add-zsh-hook
	add-zsh-hook chpwd _forge_agent_universe_guard
	_forge_agent_universe_guard

	codex() {
		local arg

		_forge_agent_universe_guard || return 1
		for arg in "$@"; do
			case "$arg" in
				-C | -C?* | --cd | --cd=* | --add-dir | --add-dir=* \
					| -s | -s=* | --sandbox | --sandbox=* \
					| -a | -a=* | --ask-for-approval | --ask-for-approval=* \
					| -c | -c=* | --config | --config=* \
					| -p | -p=* | --profile | --profile=* \
					| --approve-for-me | --dangerously-bypass-approvals-and-sandbox)
					print -u2 "Blocked Codex option inside $FORGE_AGENT_IDENTITY: $arg"
					return 2
					;;
			esac
		done

		command codex \
			-C "$PWD" \
			--sandbox workspace-write \
			--ask-for-approval on-request \
			"$@"
	}

	unset expected_universe_root
fi
