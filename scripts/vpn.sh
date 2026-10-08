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
	FORGE_LINUX_CONFIG_HOME="${FORGE_HOME_ROOT:-${XDG_CONFIG_HOME:-${HOME}/.config}/forge}"
	FORGE_SECRETS_FILE="${FORGE_LINUX_SECRETS_FILE:-${FORGE_LINUX_CONFIG_HOME}/forge-secrets.sh}"
	if [[ ! -f "$FORGE_SECRETS_FILE" && -f /data/forge/forge-secrets.sh ]]; then
		FORGE_SECRETS_FILE="/data/forge/forge-secrets.sh"
	fi
fi

# Load secrets
if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then source "$FORGE_SECRETS_FILE"; fi

FORGE_VPN_CONFIG_FILE="${FORGE_VPN_CONFIG_FILE:-${FORGE_ROOT:-$HOME/mac-forge}/config-local/vpn-connections.json}"

#######################################
# Helper: choose VPN from state json
#######################################
choose_vpn() {
	local selected
	if [[ -f "$FORGE_VPN_CONFIG_FILE" ]]; then
		# Fields are joined with \x1f (unit separator), not a tab: tab is an
		# IFS whitespace character, so "IFS=$'\t' read" silently squeezes
		# consecutive empty fields (e.g. an empty servercert) together,
		# shifting every field after it.
		selected="$(python3 - "$FORGE_VPN_CONFIG_FILE" <<'PY' | fzf --prompt='Select VPN: ' --with-nth=1,2 --delimiter=$'\x1f' --height=10 --border
import json, sys
with open(sys.argv[1], "r") as fp:
    state = json.load(fp)
for entry in state.get("vpn-connections", []):
    print("\x1f".join([entry.get('title',''), entry.get('url',''), entry.get('user',''), entry.get('id',''), entry.get('servercert',''), entry.get('dnsDomain','')]))
PY
		)" || return 1
		printf '%s\n' "$selected"
	fi
}

#######################################
# Main
#######################################
main() {
	local selection title url user vpn_id cert dns_domain vpn_pwd pwd_var

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
		echo "ERROR: No VPN connection is configured in $FORGE_VPN_CONFIG_FILE." >&2
		exit 1
	}
	IFS=$'\x1f' read -r title url user vpn_id cert dns_domain <<< "$selection"

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

	# Linux-only: snapshot existing tun interfaces so the one openconnect
	# creates for this connection can be identified afterwards. "|| true"
	# keeps a missing/failing `ip` from aborting the script under set -e/
	# pipefail; the DNS-domain step below degrades to a warning instead.
	local pre_tun_ifaces=""
	if [[ "$(uname -s)" == "Linux" ]]; then
		pre_tun_ifaces="$(ip -o link show type tun 2>/dev/null | awk -F': ' '{print $2}')" || true
	fi

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

	# Linux-only: systemd-resolved treats "*.local" as a reserved mDNS
	# domain and refuses unicast lookups for it unless an interface
	# explicitly claims routing authority for that domain. The Fortinet
	# gateway only pushes DNS servers/routes, not a search domain, so
	# claim it here when configured. macOS is untouched (scutil/openconnect
	# handle DNS natively there).
	if [[ "$(uname -s)" == "Linux" && -n "$dns_domain" ]] && command -v resolvectl >/dev/null 2>&1; then
		local post_tun_ifaces new_iface_list new_iface
		post_tun_ifaces="$(ip -o link show type tun 2>/dev/null | awk -F': ' '{print $2}')" || true
		# Capture the full diff before taking its first line, rather than
		# piping into `head`, so closing the read end early can't SIGPIPE
		# `comm` under pipefail.
		new_iface_list="$(comm -13 <(printf '%s\n' "$pre_tun_ifaces" | sort) <(printf '%s\n' "$post_tun_ifaces" | sort) 2>/dev/null)" || true
		new_iface="${new_iface_list%%$'\n'*}"
		if [[ -n "$new_iface" ]]; then
			# resolvectl's SetLinkDomains is auth_admin_keep under polkit;
			# use sudo explicitly rather than relying on any local polkit
			# rule (e.g. a wheel-group bypass) that may not exist on every
			# station.
			if sudo resolvectl domain "$new_iface" "~$dns_domain" >/dev/null 2>&1; then
				echo "DNS routing domain ~$dns_domain bound to $new_iface."
			else
				echo "WARNING: could not bind DNS routing domain ~$dns_domain to $new_iface; *.$dns_domain lookups may fail." >&2
			fi
		else
			echo "WARNING: could not detect the new tun interface; DNS routing domain ~$dns_domain was not set." >&2
		fi
	fi
}

main "$@"
