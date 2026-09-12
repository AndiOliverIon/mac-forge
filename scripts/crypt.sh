#!/usr/bin/env bash
set -euo pipefail

#######################################
# crypt - encrypt or decrypt files in the current directory, in place, using a
#         symmetric key stored in config-local/encrypt.key.
#
#   crypt encrypt  (encrypt / e)   fzf multi-select files and encrypt them.
#   crypt decrypt  (decrypt / de)  fzf multi-select files and decrypt them.
#
# Encrypted files are rewritten as a marker line followed by base64 AES-256-CBC
# ciphertext, so decrypt can tell encrypted files apart from plaintext.
#######################################

MARKER="#FORGE-ENC-v1"

die() {
	echo "✖ $*" >&2
	exit 1
}

warn() {
	echo "• $*" >&2
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd openssl
require_cmd fzf
require_cmd find

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="${FORGE_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
CONFIG_LOCAL_DIR="${FORGE_CONFIG_LOCAL_DIR:-$FORGE_ROOT/config-local}"
KEY_FILE="${FORGE_ENCRYPT_KEY_FILE:-$CONFIG_LOCAL_DIR/encrypt.key}"

file_mode() {
	# Print octal permission bits of a file, portable across macOS/Linux.
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || true
}

ensure_key_for_encrypt() {
	if [[ ! -s "$KEY_FILE" ]]; then
		mkdir -p "$CONFIG_LOCAL_DIR"
		umask 077
		openssl rand -base64 48 >"$KEY_FILE"
		chmod 600 "$KEY_FILE"
		warn "No encryption key found; generated a new one at:"
		warn "  $KEY_FILE"
		warn "BACK IT UP. Without this exact key you cannot decrypt these files."
	fi
	[[ -s "$KEY_FILE" ]] || die "Encryption key is empty: $KEY_FILE"
}

ensure_key_for_decrypt() {
	[[ -s "$KEY_FILE" ]] || die "Encryption key not found at $KEY_FILE; cannot decrypt."
}

is_encrypted() {
	local first
	IFS= read -r first <"$1" 2>/dev/null || true
	[[ "$first" == "$MARKER" ]]
}

encrypt_one() {
	local f="$1" tmp mode
	[[ -f "$f" ]] || {
		warn "skip (not a file): $f"
		return 0
	}
	if is_encrypted "$f"; then
		warn "skip (already encrypted): $f"
		return 0
	fi
	tmp="$(mktemp "${TMPDIR:-/tmp}/crypt.XXXXXX")"
	if ! {
		printf '%s\n' "$MARKER"
		openssl enc -aes-256-cbc -pbkdf2 -salt -a -pass file:"$KEY_FILE" -in "$f"
	} >"$tmp" 2>/dev/null; then
		rm -f "$tmp"
		die "Encryption failed for: $f"
	fi
	mode="$(file_mode "$f")"
	mv "$tmp" "$f"
	[[ -n "$mode" ]] && chmod "$mode" "$f" 2>/dev/null || true
	echo "🔒 Encrypted: $f"
}

decrypt_one() {
	local f="$1" tmp mode
	[[ -f "$f" ]] || {
		warn "skip (not a file): $f"
		return 0
	}
	if ! is_encrypted "$f"; then
		warn "skip (not encrypted): $f"
		return 0
	fi
	tmp="$(mktemp "${TMPDIR:-/tmp}/crypt.XXXXXX")"
	if ! tail -n +2 "$f" | openssl enc -d -aes-256-cbc -pbkdf2 -a -pass file:"$KEY_FILE" >"$tmp" 2>/dev/null; then
		rm -f "$tmp"
		die "Decryption failed for: $f (wrong key or corrupted file?)"
	fi
	mode="$(file_mode "$f")"
	mv "$tmp" "$f"
	[[ -n "$mode" ]] && chmod "$mode" "$f" 2>/dev/null || true
	echo "🔓 Decrypted: $f"
}

#######################################
# Main
#######################################
action="${1:-}"
[[ $# -gt 0 ]] && shift || true

case "$action" in
encrypt | decrypt) ;;
*) die "Usage: crypt <encrypt|decrypt>" ;;
esac

file_list="$(find . -maxdepth 1 -type f | sed 's|^\./||' | sort)"
[[ -n "${file_list//$'\n'/}" ]] || die "No files found in current folder: $PWD"

selected="$(
	printf '%s\n' "$file_list" \
		| fzf --multi \
			--prompt="${action} (Tab to multi-select) > " \
			--height=60% --reverse --border \
			--header="Select files to ${action} in: $PWD"
)" || true
[[ -n "${selected//$'\n'/}" ]] || die "Nothing selected."

declare -a targets=()
while IFS= read -r line; do
	[[ -n "$line" ]] || continue
	targets+=("$line")
done <<<"$selected"

echo
echo "About to ${action} ${#targets[@]} file(s) in $PWD:"
printf '  - %s\n' "${targets[@]}"
echo
read -r -p "Proceed to ${action} these files in place? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."

if [[ "$action" == "encrypt" ]]; then
	ensure_key_for_encrypt
else
	ensure_key_for_decrypt
fi

for f in "${targets[@]}"; do
	if [[ "$action" == "encrypt" ]]; then
		encrypt_one "$f"
	else
		decrypt_one "$f"
	fi
done

echo
echo "✔ Done."
