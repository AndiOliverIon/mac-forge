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
    # shellcheck disable=SC1091
    source "$HOME/mac-forge/forge.sh"
fi


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

load_secrets() {
    if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$FORGE_SECRETS_FILE"
    fi
}

#######################################
# Validate input argument
#######################################
[[ $# -eq 1 ]] || die "Usage: ./db-snapshot.sh <snapshotName>"

SNAPSHOT_SUFFIX="$1"


#######################################
# Ensure container exists & secrets loaded
#######################################
require_cmd docker
load_secrets


#######################################
# Wait for SQL Server ready
#######################################
wait_for_sql_ready() {
    echo "Waiting for SQL Server in container '$FORGE_SQL_DOCKER_CONTAINER' to be ready..."

    local max_tries=30

    for ((i=1; i<=max_tries; i++)); do
        if docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
                -S localhost \
                -U sa \
                -P "$FORGE_SQL_SA_PASSWORD" \
                -C \
                -Q "SELECT 1" >/dev/null 2>&1; then

            echo "SQL Server is ready (attempt $i)."
            return 0
        fi

        echo "  ... not ready yet (attempt $i)"
        sleep 2
    done

    die "SQL Server did not become ready after $((max_tries * 2)) seconds."
}


#######################################
# Check container
#######################################
docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$" \
    || die "SQL container '${FORGE_SQL_DOCKER_CONTAINER}' is not running."

wait_for_sql_ready


#######################################
# Step 1 — List databases and select one via fzf
#######################################
require_cmd fzf

echo "Retrieving database list..."

# Use SET NOCOUNT ON to avoid "(X rows affected)"
# -h -1  = no header
# -W     = trim trailing spaces
mapfile -t DB_LIST < <(
    docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
        /opt/mssql-tools18/bin/sqlcmd \
            -S localhost \
            -U sa \
            -P "$FORGE_SQL_SA_PASSWORD" \
            -C \
            -h -1 \
            -W \
            -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb');" \
        | sed '/^$/d'
)

(( ${#DB_LIST[@]} > 0 )) || die "No user databases found."

DB_SELECTED="$(
    printf '%s\n' "${DB_LIST[@]}" | fzf --prompt="Select database to snapshot > "
)" || die "No database selected."

echo "Selected database: $DB_SELECTED"


#######################################
# Step 2 — Create snapshots folder if missing
#######################################
SNAPSHOT_DIR="$FORGE_SQL_SNAPSHOTS_PATH"
mkdir -p "$SNAPSHOT_DIR"

SNAPSHOT_NAME="${DB_SELECTED}_${SNAPSHOT_SUFFIX}.bak"
SNAPSHOT_PATH_CONTAINER="${FORGE_SQL_DOCKER_BACKUP_PATH}/${SNAPSHOT_NAME}"
SNAPSHOT_PATH_HOST="${SNAPSHOT_DIR}/${SNAPSHOT_NAME}"


#######################################
# Step 3 — Execute SQL backup command
#######################################
echo "Creating snapshot: $SNAPSHOT_NAME"

docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
    /opt/mssql-tools18/bin/sqlcmd \
        -S localhost \
        -U sa \
        -P "$FORGE_SQL_SA_PASSWORD" \
        -C \
        -b \
        -Q "BACKUP DATABASE [$DB_SELECTED] TO DISK = N'$SNAPSHOT_PATH_CONTAINER' WITH INIT;"

# Copy from container to host snapshot folder
docker cp "${FORGE_SQL_DOCKER_CONTAINER}:${SNAPSHOT_PATH_CONTAINER}" "$SNAPSHOT_PATH_HOST"

echo "✔ Snapshot created at:"
echo "  $SNAPSHOT_PATH_HOST"
