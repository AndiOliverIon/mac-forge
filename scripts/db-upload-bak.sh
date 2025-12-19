#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
else
	if [[ -f "$HOME/mac-forge/forge.sh" ]]; then
		# shellcheck disable=SC1091
		source "$HOME/mac-forge/forge.sh"
	else
		echo "✖ forge.sh not found next to this script or at \$HOME/mac-forge/forge.sh" >&2
		exit 1
	fi
fi

#######################################
# Helpers
#######################################
die() {
	echo "✖ $*" >&2
	exit 1
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }
log_step() { echo "→ $*"; }
log_ok() { echo "✔ $*"; }

#######################################
# Requirements
#######################################
require_cmd docker
require_cmd fzf
require_cmd find
require_cmd sed
require_cmd sort

#######################################
# Config
#######################################
CONTAINER="${FORGE_SQL_DOCKER_CONTAINER:-forge-sql}"
CONTAINER_IMPORT_DIR="/var/opt/mssql/backups" # container-local (not host-mounted)
PWD_DIR="$(pwd)"

#######################################
# Preconditions
#######################################
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" ||
	die "Container '$CONTAINER' is not running. Start it first."

#######################################
# Pick a .bak from current folder
#######################################
log_step "Searching for .bak files under: $PWD_DIR"

# Build the fzf list directly; avoid mapfile
SELECTED_REL="$(
	find "$PWD_DIR" -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print |
		sort |
		sed "s|^$PWD_DIR/||" |
		fzf --prompt="Select .bak to upload > " --height=40% --reverse
)" || true

[[ -n "${SELECTED_REL:-}" ]] || die "No file selected (or no .bak/.bkp files found)."

HOST_FILE="$PWD_DIR/$SELECTED_REL"
[[ -f "$HOST_FILE" ]] || die "Selected file not found: $HOST_FILE"

BASENAME="$(basename "$HOST_FILE")"
CONTAINER_FILE="$CONTAINER_IMPORT_DIR/$BASENAME"

#######################################
# Ensure container directory exists
#######################################
log_step "Preparing container import folder: $CONTAINER_IMPORT_DIR"
docker exec "$CONTAINER" bash -lc "mkdir -p '$CONTAINER_IMPORT_DIR' && chmod 755 '$CONTAINER_IMPORT_DIR'"

#######################################
# Upload into container
#######################################
log_step "Uploading to container '$CONTAINER'..."
docker cp "$HOST_FILE" "$CONTAINER:$CONTAINER_FILE"

#######################################
# Fix permissions
#######################################
log_step "Fixing ownership for SQL Server (mssql)..."
docker exec "$CONTAINER" bash -lc "chown mssql:mssql '$CONTAINER_FILE' && chmod 644 '$CONTAINER_FILE'"

#######################################
# Summary
#######################################
log_ok "Uploaded:"
echo "  Host:      $HOST_FILE"
echo "  Container: $CONTAINER_FILE"
echo
echo "Use this path in SSMS restore:"
echo "  $CONTAINER_FILE"
