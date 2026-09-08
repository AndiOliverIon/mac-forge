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

GENERATED_LENGTH=24
GENERATED_CHARSET='A-Za-z0-9!@#$%^&*()_+=-'

#######################################
# Args
#######################################
FORCE=0
while getopts ":f" opt; do
	case "$opt" in
	f) FORCE=1 ;;
	*) die "Usage: pwa [-f] <category/name>" ;;
	esac
done
shift $((OPTIND - 1))

ENTRY="${1:-}"
[[ -n "$ENTRY" ]] || die "Usage: pwa [-f] <category/name>"

STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
[[ -d "$STORE_DIR" ]] || die "Password store not found at $STORE_DIR. Run 'pass init' first."

ENTRY_FILE="$STORE_DIR/$ENTRY.gpg"
if [[ -f "$ENTRY_FILE" && $FORCE -eq 0 ]]; then
	die "$ENTRY already exists. Use -f to overwrite."
fi

#######################################
# Password: typed (with confirmation) or auto-generated
#######################################
read -r -s -p "Password (leave blank to auto-generate): " password
echo

if [[ -z "$password" ]]; then
	password="$(LC_ALL=C tr -dc "$GENERATED_CHARSET" </dev/urandom | head -c "$GENERATED_LENGTH" || true)"
	echo "✔ Generated password: $password"
else
	read -r -s -p "Confirm password: " password_confirm
	echo
	[[ "$password" == "$password_confirm" ]] || die "Passwords did not match."
fi

#######################################
# Optional account/username and description lines
#######################################
read -r -p "Account/username (optional): " account
read -r -p "Description/notes (optional): " description

{
	echo "$password"
	echo "$account"
	[[ -n "$description" ]] && echo "$description"
} | pass insert -m -f "$ENTRY" >/dev/null

echo "✔ Added $ENTRY"
