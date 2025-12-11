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

# Always use sa for this workflow (default if unset)
FORGE_SQL_USER="${FORGE_SQL_USER:-sa}"

# Required variables (same style as migrations script)
: "${FORGE_SQL_DOCKER_CONTAINER:?FORGE_SQL_DOCKER_CONTAINER must be set in forge.sh}"
: "${FORGE_SQL_USER:?FORGE_SQL_USER must be set (probably in forge-secrets.sh)}"
: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set (probably in forge-secrets.sh)}"

# Host & port to connect from the host (container exposed to host)
FORGE_SQL_HOST="${FORGE_SQL_HOST:-localhost}"
FORGE_SQL_PORT="${FORGE_SQL_PORT:-1433}"

if ! command -v docker >/dev/null 2>&1; then
	echo "docker is required but not found in PATH." >&2
	exit 1
fi

if ! command -v sqlcmd >/dev/null 2>&1; then
	echo "sqlcmd is required but not found in PATH. Install with: brew install sqlcmd" >&2
	exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
	echo "fzf is required but not found in PATH." >&2
	exit 1
fi

#######################################
# Helpers: container / DB selection
#######################################
ensure_container_running() {
	if ! docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"; then
		echo "SQL container '$FORGE_SQL_DOCKER_CONTAINER' is not running. Start it and retry." >&2
		exit 1
	fi
}

list_databases() {
	sqlcmd \
		-S "${FORGE_SQL_HOST},${FORGE_SQL_PORT}" \
		-U "$FORGE_SQL_USER" \
		-P "$FORGE_SQL_SA_PASSWORD" \
		-Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;" \
		-h -1 -W 2>/dev/null | tr -d '\r' || return 1
}

choose_database() {
	local dbs selected

	# log to stderr, not stdout
	echo "Querying databases from container '$FORGE_SQL_DOCKER_CONTAINER'..." >&2
	dbs="$(list_databases)"
	if [[ -z "${dbs// /}" ]]; then
		echo "No user databases found (or query failed)." >&2
		return 1
	fi

	selected="$(printf '%s\n' "$dbs" | fzf --prompt='Select database for COMPLETECOMP: ' --height=20 --border)"
	if [[ -z "${selected:-}" ]]; then
		echo "No database selected. Aborting." >&2
		return 1
	fi

	printf '%s\n' "$selected"
}

#######################################
# Helper: sqlcmd wrapper
#######################################
forge_sqlcmd() {
	local db="$1"
	shift
	sqlcmd \
		-S "${FORGE_SQL_HOST},${FORGE_SQL_PORT}" \
		-U "$FORGE_SQL_USER" \
		-P "$FORGE_SQL_SA_PASSWORD" \
		-d "$db" \
		-b -C "$@"
}

#######################################
# Args: --from, --to, --ssi-id, --db
#######################################
FROM_SEQ_NO=""
TO_SEQ_NO=""
SSI_ID=""
DB_NAME=""

usage() {
	cat <<EOF
Usage: $(basename "$0") [--from N] [--to N] [--ssi-id ID] [--db NAME]

Completes all plannings based on provided sequence range and/or SSI id:
  --from N      Minimum SeqNo (inclusive)
  --to N        Maximum SeqNo (inclusive)
  --ssi-id ID   Restrict to specific SsiId
  --db NAME     Database name. If omitted, you'll choose via fzf.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--from)
			[[ $# -ge 2 ]] || {
				echo "Missing value for --from" >&2
				exit 1
			}
			FROM_SEQ_NO="$2"
			shift 2
			;;
		--to)
			[[ $# -ge 2 ]] || {
				echo "Missing value for --to" >&2
				exit 1
			}
			TO_SEQ_NO="$2"
			shift 2
			;;
		--ssi-id)
			[[ $# -ge 2 ]] || {
				echo "Missing value for --ssi-id" >&2
				exit 1
			}
			SSI_ID="$2"
			shift 2
			;;
		--db)
			[[ $# -ge 2 ]] || {
				echo "Missing value for --db" >&2
				exit 1
			}
			DB_NAME="$2"
			shift 2
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

#######################################
# Decide database (explicit or fzf)
#######################################
ensure_container_running

if [[ -z "$DB_NAME" ]]; then
	DB_NAME="$(choose_database)" || exit 1
	echo "Selected database (fzf): $DB_NAME"
else
	echo "Using database from argument: $DB_NAME"
fi

echo "========== complete-plannings =========="
echo "Machine:          ${FORGE_MACHINE_NAME:-unknown}"
echo "SQL Host:         ${FORGE_SQL_HOST}"
echo "SQL Port:         ${FORGE_SQL_PORT}"
echo "Database:         ${DB_NAME}"
echo "User:             ${FORGE_SQL_USER}"
echo "Args:"
echo "  --from   = ${FROM_SEQ_NO:-<none>}"
echo "  --to     = ${TO_SEQ_NO:-<none>}"
echo "  --ssi-id = ${SSI_ID:-<none>}"
echo "========================================"

#######################################
# Build WHERE clause
#######################################
conditions=()

if [[ -n "$FROM_SEQ_NO" && -n "$TO_SEQ_NO" ]]; then
	conditions+=("PL.SeqNo BETWEEN $FROM_SEQ_NO AND $TO_SEQ_NO")
elif [[ -n "$FROM_SEQ_NO" ]]; then
	conditions+=("PL.SeqNo >= $FROM_SEQ_NO")
elif [[ -n "$TO_SEQ_NO" ]]; then
	conditions+=("PL.SeqNo <= $TO_SEQ_NO")
fi

if [[ -n "$SSI_ID" ]]; then
	conditions+=("PL.SsiId = $SSI_ID")
fi

WHERE_CLAUSE=""
if [[ ${#conditions[@]} -gt 0 ]]; then
	joined="${conditions[0]}"
	for ((i = 1; i < ${#conditions[@]}; i++)); do
		joined+=" AND ${conditions[i]}"
	done
	WHERE_CLAUSE="WHERE $joined"
fi

echo "WHERE clause:"
if [[ -n "$WHERE_CLAUSE" ]]; then
	echo "  $WHERE_CLAUSE"
else
	echo "  <none> (ALL plannings will be considered!)"
fi
echo "----------------------------------------"

#######################################
# Count plannings
#######################################
COUNT_SQL="
SET NOCOUNT ON;
SELECT COUNT(*) AS PlanningCount
FROM Production.Planning PL
    JOIN Common.Barcode B ON PL.SsiId = B.SsiId
    JOIN Production.Ssi S ON PL.SsiId = S.Id
    JOIN Production.Product P ON S.ProductId = P.Id AND P.ProductTypeId <> 208
$WHERE_CLAUSE;
"

echo "Running count query..."
count_output="$(forge_sqlcmd "$DB_NAME" -h -1 -W -Q "$COUNT_SQL" 2>&1 || true)"
echo "Count query raw output:"
echo "------------------------"
echo "$count_output"
echo "------------------------"

planning_count="$(echo "$count_output" | awk '/^[0-9]+$/ {val=$1} END {print val}')"
planning_count="${planning_count:-0}"

echo "Detected planning count: $planning_count"

if [[ "$planning_count" == "0" ]]; then
	echo "No plannings match the filters. Exiting without inserting activities."
	echo "========== DONE (no-op) =========="
	exit 0
fi

echo "Writing instructions for $planning_count plannings"
echo "----------------------------------------"

#######################################
# Main SQL: setup + insert activities
#######################################
MAIN_SQL="
SET NOCOUNT ON;

-- Insert missing WorkcellScanInterfaces for #COMPLETECOMP#
INSERT INTO Common.WorkcellScanInterface
    (WorkcellId, ScanInterfaceId, WorkcellTypeId, Entity, CreatedAt, CreatedBy)
SELECT
    W.Id,                        -- WorkcellId
    SI.Id,                       -- ScanInterfaceId
    W.WorkcellTypeId,
    'Workcell',                  -- Entity
    SYSDATETIME(),               -- CreatedAt
    SUSER_SNAME()                -- CreatedBy
FROM Production.Workcell W
JOIN Common.ScanInterface SI ON SI.Identifier = '#COMPLETECOMP#'
WHERE NOT EXISTS (
    SELECT 1
    FROM Common.WorkcellScanInterface WSI
    WHERE WSI.WorkcellId = W.Id
      AND WSI.ScanInterfaceId = SI.Id
);

-- Reactivate if it already exists but is deactivated
UPDATE WSI
SET IsDeactivated = 0
FROM Common.WorkcellScanInterface WSI
JOIN Common.ScanInterface SI ON WSI.ScanInterfaceId = SI.Id
WHERE SI.Identifier = '#COMPLETECOMP#'
  AND WSI.IsDeactivated = 1;

-- Insert activities for all matching plannings
INSERT INTO Sync.Activity (EventTypeId, StatusTypeId, Workcell, Parameter1, Parameter2, CreatedAt, CreatedBy)
SELECT
    10,                                                    -- EventTypeId
    1,                                                     -- StatusTypeId
    COALESCE(PL.CurrentWorkcellId, PL.WorkcellId),         -- Workcell
    '#COMPLETECOMP',                                       -- Parameter1
    B.Code,                                                -- Parameter2 (Barcode)
    GETDATE(),                                             -- CreatedAt
    'ArdisAdmin'                                           -- CreatedBy
FROM Production.Planning PL
    JOIN Common.Barcode B ON PL.SsiId = B.SsiId
    JOIN Production.Ssi S ON PL.SsiId = S.Id
    JOIN Production.Product P ON S.ProductId = P.Id AND P.ProductTypeId <> 208
$WHERE_CLAUSE
ORDER BY PL.SeqNo;

-- Report how many activities were inserted
SELECT InsertedActivitiesCount = @@ROWCOUNT;
"

echo "Executing main SQL batch (interfaces + activities)..."
main_output="$(forge_sqlcmd "$DB_NAME" -h -1 -W -Q "$MAIN_SQL" 2>&1 || true)"
echo "Main SQL raw output:"
echo "------------------------"
echo "$main_output"
echo "------------------------"

inserted_count="$(echo "$main_output" | awk '/^[0-9]+$/ {val=$1} END {print val}')"
inserted_count="${inserted_count:-0}"

echo "Inserted activities: $inserted_count"
echo "========== DONE =========="
