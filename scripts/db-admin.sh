#!/usr/bin/env bash
set -euo pipefail

#######################################
# Setup & config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
else
	echo "forge.sh not found next to this script ($SCRIPT_DIR)." >&2
	exit 1
fi

if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
	# shellcheck disable=SC1091
	source "$FORGE_SECRETS_FILE"
fi

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

tsql_ident() {
	local name="${1:?}"
	name="${name//]/]]}"
	printf '[%s]' "$name"
}

#######################################
# sqlcmd wrapper
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
	[[ -n "${dbs// /}" ]] || die "No user databases found (or query failed)."
	selected="$(printf '%s\n' "$dbs" | fzf --prompt="Database > " --height=40% --border)"
	[[ -n "${selected:-}" ]] || die "No database selected. Aborting."
	printf '%s\n' "$selected"
}

choose_action() {
	printf "%s\n" \
		"Take offline" \
		"Take online" \
		"Drop database" \
		"Set recovery SIMPLE" \
		"Set recovery FULL" \
		"Shrink database (data)" \
		"Shrink log (aggressive)" |
		fzf --prompt="Action > " --height=45% --border
}

confirm_drop() { printf "%s\n" "NO" "YES (drop it)" | fzf --prompt="Confirm drop > " --height=10 --border --no-multi; }
confirm_yesno() { printf "%s\n" "NO" "YES" | fzf --prompt="$1 > " --height=10 --border --no-multi; }

#######################################
# Info helpers
#######################################
print_db_size() {
	local db="${1:?}"

	echo "────────────────────────────────────────"
	echo "DB size snapshot for '$db'"

	forge_sqlcmd "$db" -Q "SET NOCOUNT ON; EXEC sp_spaceused;" -W

	echo ""
	echo "Recovery model:"
	forge_sqlcmd "master" -Q "
SET NOCOUNT ON;
SELECT name, recovery_model_desc
FROM sys.databases
WHERE name = N'$(printf "%s" "$db" | sed "s/'/''/g")';
" -W

	echo ""
	echo "Files (allocated vs used):"
	forge_sqlcmd "$db" -Q "
SET NOCOUNT ON;

SELECT
    df.name AS file_name,
    df.type_desc AS file_type,
    CAST(df.size / 128.0 AS DECIMAL(18,2)) AS allocated_mb,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS DECIMAL(18,2)) AS used_mb,
    CAST((df.size - FILEPROPERTY(df.name,'SpaceUsed')) / 128.0 AS DECIMAL(18,2)) AS free_mb,
    df.physical_name
FROM sys.database_files df
ORDER BY df.type_desc, df.name;
" -W

	echo "────────────────────────────────────────"
}

get_log_file_name() {
	local db="${1:?}"
	forge_sqlcmd "$db" -Q "
SET NOCOUNT ON;
SELECT TOP(1) name FROM sys.database_files WHERE type_desc='LOG' ORDER BY name;
" -h -1 -W 2>/dev/null | tr -d '\r' | sed '/^$/d' | head -n 1
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

	"Set recovery SIMPLE")
		confirm="$(confirm_yesno "Switch recovery to SIMPLE (breaks log backup chain)?" || true)"
		[[ "$confirm" == "YES" ]] || {
			echo "✖ Cancelled."
			exit 0
		}

		echo "→ BEFORE:"
		print_db_size "$DB_NAME"

		forge_sqlcmd "master" -Q "ALTER DATABASE $DB_IDENT SET RECOVERY SIMPLE WITH NO_WAIT;" -W
		# Checkpoint helps truncate under SIMPLE
		forge_sqlcmd "$DB_NAME" -Q "CHECKPOINT;" -W

		echo "→ AFTER:"
		print_db_size "$DB_NAME"
		echo "✔ '$DB_NAME' set to SIMPLE."
		;;

	"Set recovery FULL")
		confirm="$(confirm_yesno "Switch recovery to FULL (you should take a full backup to start a new chain)?" || true)"
		[[ "$confirm" == "YES" ]] || {
			echo "✖ Cancelled."
			exit 0
		}

		echo "→ BEFORE:"
		print_db_size "$DB_NAME"

		forge_sqlcmd "master" -Q "ALTER DATABASE $DB_IDENT SET RECOVERY FULL WITH NO_WAIT;" -W

		echo "→ AFTER:"
		print_db_size "$DB_NAME"
		echo "✔ '$DB_NAME' set to FULL."
		;;

	"Shrink database (data)")
		confirm="$(confirm_yesno "Run DBCC SHRINKDATABASE (can fragment indexes)?" || true)"
		[[ "$confirm" == "YES" ]] || {
			echo "✖ Cancelled."
			exit 0
		}

		echo "→ BEFORE:"
		print_db_size "$DB_NAME"

		forge_sqlcmd "$DB_NAME" -Q "
SET NOCOUNT ON;
DBCC SHRINKDATABASE ($DB_IDENT, 10) WITH NO_INFOMSGS;
" -W

		echo "→ AFTER:"
		print_db_size "$DB_NAME"
		echo "✔ '$DB_NAME' data shrink finished."
		;;

	"Shrink log (aggressive)")
		confirm="$(confirm_yesno "Shrink LOG now (best after SIMPLE + CHECKPOINT)?" || true)"
		[[ "$confirm" == "YES" ]] || {
			echo "✖ Cancelled."
			exit 0
		}

		echo "→ BEFORE:"
		print_db_size "$DB_NAME"

		# Ensure SIMPLE truncation opportunity
		forge_sqlcmd "$DB_NAME" -Q "CHECKPOINT;" -W

		LOG_FILE="$(get_log_file_name "$DB_NAME" || true)"
		[[ -n "${LOG_FILE:-}" ]] || die "Could not determine log file name."

		# Shrink log to minimum target (0 = as small as possible)
		forge_sqlcmd "$DB_NAME" -Q "
SET NOCOUNT ON;
DBCC SHRINKFILE (N'${LOG_FILE//\'/\'\'}', 0) WITH NO_INFOMSGS;
" -W

		echo "→ AFTER:"
		print_db_size "$DB_NAME"
		echo "✔ '$DB_NAME' log shrink finished."
		;;

	*)
		die "Unknown action: $ACTION"
		;;
esac
