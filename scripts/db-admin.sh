#!/usr/bin/env bash
set -euo pipefail

#######################################
# Setup & config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load forge config
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
else
	echo "forge.sh not found next to this script ($SCRIPT_DIR)." >&2
	exit 1
fi

# Optionally load secrets (SQL user/pwd etc.)
if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
	# shellcheck disable=SC1091
	source "$FORGE_SECRETS_FILE"
fi

# Defaults / requireds (mirror your other script)
FORGE_SQL_USER="${FORGE_SQL_USER:-sa}"

: "${FORGE_SQL_DOCKER_CONTAINER:?FORGE_SQL_DOCKER_CONTAINER must be set in forge.sh}"
: "${FORGE_SQL_USER:?FORGE_SQL_USER must be set (probably in forge-secrets.sh)}"
: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set (probably in forge-secrets.sh)}"

FORGE_SQL_HOST="${FORGE_SQL_HOST:-localhost}"
FORGE_SQL_PORT="${FORGE_SQL_PORT:-1433}"

#######################################
# Helpers
#######################################
die() {
	echo "✖ $*" >&2
	exit 1
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

ensure_container_running() {
	if ! docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"; then
		die "SQL container '$FORGE_SQL_DOCKER_CONTAINER' is not running. Start it and retry."
	fi
}

# Quote DB name safely in [brackets] for T-SQL identifiers
tsql_ident() {
	local name="${1:?}"
	name="${name//]/]]}"
	printf '[%s]' "$name"
}

#######################################
# sqlcmd wrapper (host -> container port)
#######################################
forge_sqlcmd() {
	local db="${1:-}"
	shift || true

	local -a args=(
		-S "${FORGE_SQL_HOST},${FORGE_SQL_PORT}"
		-U "$FORGE_SQL_USER"
		-P "$FORGE_SQL_SA_PASSWORD"
		-b
		-C
	)

	if [[ -n "$db" ]]; then
		args+=(-d "$db")
	fi

	sqlcmd "${args[@]}" "$@"
}

#######################################
# DB list & pick
#######################################
list_databases() {
	forge_sqlcmd "" \
		-Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;" \
		-h -1 -W 2>/dev/null | tr -d '\r'
}

choose_database() {
	local dbs selected
	echo "Querying databases from container '$FORGE_SQL_DOCKER_CONTAINER'..." >&2

	dbs="$(list_databases || true)"
	if [[ -z "${dbs// /}" ]]; then
		die "No user databases found (or query failed)."
	fi

	selected="$(printf '%s\n' "$dbs" | fzf --prompt="Database > " --height=40% --border)"
	[[ -n "${selected:-}" ]] || die "No database selected. Aborting."
	printf '%s\n' "$selected"
}

choose_action() {
	printf "%s\n" \
		"Take offline" \
		"Take online" \
		"Drop database" |
		fzf --prompt="Action > " --height=40% --border
}

confirm_drop() {
	# Very explicit confirmation to avoid fat-finger drops
	printf "%s\n" "NO" "YES (drop it)" | fzf --prompt="Confirm drop > " --height=10 --border --no-multi
}

#######################################
# Main
#######################################
require_cmd docker
require_cmd sqlcmd
require_cmd fzf

ensure_container_running

DB_NAME="$(choose_database)"
ACTION="$(choose_action)"
[[ -n "${ACTION:-}" ]] || exit 0

DB_IDENT="$(tsql_ident "$DB_NAME")"

case "$ACTION" in
	"Take offline")
		forge_sqlcmd "" -Q "ALTER DATABASE $DB_IDENT SET OFFLINE WITH ROLLBACK IMMEDIATE;"
		echo "✔ '$DB_NAME' is now OFFLINE."
		;;

	"Take online")
		forge_sqlcmd "" -Q "ALTER DATABASE $DB_IDENT SET ONLINE;"
		echo "✔ '$DB_NAME' is now ONLINE."
		;;

	"Drop database")
		confirm="$(confirm_drop || true)"
		[[ "$confirm" == "YES (drop it)" ]] || {
			echo "✖ Drop cancelled."
			exit 0
		}

		forge_sqlcmd "" -Q "ALTER DATABASE $DB_IDENT SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB_IDENT;"
		echo "✔ '$DB_NAME' dropped."
		;;

	*)
		die "Unknown action: $ACTION"
		;;
esac
