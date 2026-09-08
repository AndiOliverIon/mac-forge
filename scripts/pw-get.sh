#!/usr/bin/env bash
set -euo pipefail

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

require_cmd pass
require_cmd fzf

CLIP_TIME="${PASSWORD_STORE_CLIP_TIME:-45}"

#######################################
# Clipboard via OSC 52: writes to the terminal escape stream instead of a
# local display, so it reaches whatever terminal you're actually looking at
# -- works the same whether this runs locally or over ssh. Requires the
# terminal emulator to support OSC 52 clipboard writes.
#######################################
osc52_copy() {
	local data="$1"
	local b64
	b64="$(printf '%s' "$data" | base64 | tr -d '\n')"
	printf '\033]52;c;%s\a' "$b64" >/dev/tty
}

osc52_clear_later() {
	(
		sleep "$CLIP_TIME"
		printf '\033]52;c;\a' >/dev/tty
	) >/dev/null 2>&1 &
	disown
}

copy_line() {
	local entry="$1" line_no="$2" label="$3"
	local value
	value="$(pass show "$entry" | sed -n "${line_no}p")"
	[[ -n "$value" ]] || die "No $label stored for $entry."
	osc52_copy "$value"
	osc52_clear_later
	echo "✔ Copied $label for $entry to clipboard (clears in ${CLIP_TIME}s)"
}

STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
[[ -d "$STORE_DIR" ]] || die "Password store not found at $STORE_DIR. Run 'pass init' first."

#######################################
# Build the flat entry list (strip store dir, .git, and .gpg suffix)
#######################################
mapfile -t entries < <(
	find "$STORE_DIR" -path "$STORE_DIR/.git" -prune -o -type f -name '*.gpg' -print |
		sed -e "s|^$STORE_DIR/||" -e 's/\.gpg$//' |
		sort
)

((${#entries[@]} > 0)) || die "Password store is empty. Add one with: pwa <category/name>"

# Warm the GPG cache with one clean, uninterrupted decrypt before fzf starts.
# Without this, the live preview's per-entry decrypt can race a passphrase
# prompt against fast navigation and lose -- fzf kills the preview process
# for the entry you've moved off of, silently discarding its output.
pass show "${entries[0]}" >/dev/null 2>&1 || true

#######################################
# Fuzzy-pick an entry; --expect reports which key closed fzf
#######################################
mapfile -t result < <(
	printf '%s\n' "${entries[@]}" |
		fzf --height=60% --reverse \
			--header='enter: copy password   ctrl-u: copy account   ctrl-y: show entry' \
			--preview 'desc="$(pass show {} 2>/dev/null | sed -n "3p")"; printf "%s\n" "${desc:-(no description)}"' \
			--preview-window=up:1:wrap \
			--expect=ctrl-u,ctrl-y
)

key="${result[0]:-}"
entry="${result[1]:-}"

[[ -n "$entry" ]] || { echo "✋ Cancelled."; exit 0; }

#######################################
# Act on the selection
#######################################
case "$key" in
ctrl-u)
	copy_line "$entry" 2 "account"
	;;
ctrl-y)
	mapfile -t lines < <(pass show "$entry")
	echo "$entry"
	echo "────────────────"
	printf '%-12s %s\n' "password:" "${lines[0]:-}"
	printf '%-12s %s\n' "account:" "${lines[1]:-(none)}"
	[[ -n "${lines[2]:-}" ]] && printf '%-12s %s\n' "description:" "${lines[2]}"
	;;
*)
	copy_line "$entry" 1 "password"
	;;
esac
