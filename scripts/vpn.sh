#!/usr/bin/env bash
set -euo pipefail

#######################################
# Setup & config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load forge config
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then source "$SCRIPT_DIR/forge.sh";
elif [[ -f "$HOME/mac-forge/scripts/forge.sh" ]]; then source "$HOME/mac-forge/scripts/forge.sh";
fi

# Linux keeps private Forge configuration outside the repository and iCloud.
if [[ "$(uname -s)" == "Linux" ]]; then
	FORGE_SECRETS_FILE="${FORGE_LINUX_SECRETS_FILE:-${FORGE_HOME_ROOT:-/data/forge}/forge-secrets.sh}"
fi

# Load secrets
if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then source "$FORGE_SECRETS_FILE"; fi

#######################################
# Helper: choose VPN from state json
#######################################
choose_vpn() {
	local selected
	if [[ -f "${FORGE_WORK_STATE_FILE:-}" ]]; then
		selected="$(python3 - "$FORGE_WORK_STATE_FILE" <<'PY' | fzf --prompt='Select VPN: ' --with-nth=1,2 --delimiter=$'\t' --height=10 --border
import json, sys
with open(sys.argv[1], "r") as fp:
    state = json.load(fp)
for entry in state.get("vpn-connections", []):
    print(f"{entry.get('title')}\t{entry.get('url')}\t{entry.get('user')}\t{entry.get('id')}\t{entry.get('servercert','')}")
PY
		)" || return 1
		printf '%s\n' "$selected"
	fi
}

#######################################
# Main
#######################################
main() {
	local selection title url user vpn_id cert vpn_pwd pwd_var

	command -v openconnect >/dev/null 2>&1 || {
		echo "ERROR: openconnect is not installed." >&2
		exit 1
	}

	# Kill existing first for a clean state
	if pgrep openconnect >/dev/null; then
		sudo pkill -SIGINT openconnect
		sleep 1
	fi

	selection="$(choose_vpn)" || exit 1
	[[ -n "$selection" ]] || {
		echo "ERROR: No VPN connection is configured in $FORGE_WORK_STATE_FILE." >&2
		exit 1
	}
	IFS=$'\t' read -r title url user vpn_id cert <<< "$selection"

	# Construct secret variable name (e.g., FORGE_VPN_ARDIS_PASSWORD)
	pwd_var="FORGE_VPN_${vpn_id}_PASSWORD"

	# Dynamically get the password from the environment (loaded from secrets)
	vpn_pwd="${!pwd_var:-}"
	[[ -n "$vpn_pwd" ]] || {
		echo "ERROR: $pwd_var is missing from $FORGE_SECRETS_FILE." >&2
		exit 1
	}

	echo -n "Connecting to $title... "
	sudo -v # Cache sudo

	# Use --background and --passwd-on-stdin for fire-and-forget
	# Redirecting output to a temp file to capture errors if backgrounding fails
	local log_file="/tmp/vpn_connect.log"
	
	if printf "%s\n" "$vpn_pwd" | sudo openconnect \
		--protocol=fortinet \
		--user="$user" \
		--servercert "$cert" \
		--useragent "FortiClient macOS" \
		--passwd-on-stdin \
		--background \
		--non-inter \
		"$url" >"$log_file" 2>&1; then
		echo "CONNECTED."
	else
		echo "FAILED."
		cat "$log_file"
		exit 1
	fi
}

main "$@"
