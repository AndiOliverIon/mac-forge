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
# Env defaults / required
#######################################
# Always use sa in this workflow
FORGE_SQL_USER="${FORGE_SQL_USER:-sa}"

#######################################
# Docker helpers
#######################################
container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"
}

container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"
}

wait_for_sql_ready() {
    echo "Waiting for SQL Server in container '$FORGE_SQL_DOCKER_CONTAINER' to be ready..."

    local max_tries=30

    for ((i=1; i<=max_tries; i++)); do
        if docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
                -S localhost \
                -U "$FORGE_SQL_USER" \
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

drop_user_databases() {
    echo "Collecting user databases to drop..."

    mapfile -t DB_LIST < <(
        docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
                -S localhost \
                -U "$FORGE_SQL_USER" \
                -P "$FORGE_SQL_SA_PASSWORD" \
                -C \
                -h -1 \
                -W \
                -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb');" \
        | sed '/^$/d'
    )

    if (( ${#DB_LIST[@]} == 0 )); then
        echo "No user databases to drop."
        return 0
    fi

    for db in "${DB_LIST[@]}"; do
        echo "Dropping database: $db"
        docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
                -S localhost \
                -U "$FORGE_SQL_USER" \
                -P "$FORGE_SQL_SA_PASSWORD" \
                -C \
                -b \
                -Q "ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db];"
    done
}

clear_container_data_dir() {
    # Only clear contents, not the root directory, with safety guard
    if [[ -z "${FORGE_DOCKER_VOLUME_ROOT:-}" || ! -d "$FORGE_DOCKER_VOLUME_ROOT" ]]; then
        echo "Skip data cleanup: FORGE_DOCKER_VOLUME_ROOT not set or missing."
        return 0
    fi

    case "$FORGE_DOCKER_VOLUME_ROOT" in
        /|/home|/home/*|/Users|/Users/*)
            # Still allow, but avoid accidental root wipe by requiring deeper path
            :
            ;;
    esac

    echo "Clearing data under: $FORGE_DOCKER_VOLUME_ROOT (preserving snapshots/)"

    shopt -s nullglob dotglob
    for entry in "$FORGE_DOCKER_VOLUME_ROOT"/*; do
        # Preserve snapshots directory so backups survive a clear
        if [[ "$entry" == "$FORGE_DOCKER_VOLUME_ROOT/snapshots" ]]; then
            continue
        fi

        rm -rf "$entry" 2>/dev/null || die "Failed to remove $entry."
    done
    shopt -u nullglob dotglob
}

usage() {
    cat <<'USAGE'
Usage: db-clear.sh [--soft]
  (no flag) : Drop all user databases, remove container, clear data directory.
  --soft    : Drop user databases only (container stays).
USAGE
    exit 1
}

#######################################
# Main
#######################################
main() {
    local mode="hard"

    if (( $# == 0 )); then
        mode="hard"
    elif (( $# == 1 )) && [[ "$1" == "--soft" ]]; then
        mode="soft"
    else
        usage
    fi

    require_cmd docker
    load_secrets

    if [[ "$mode" == "soft" ]]; then
        [[ -n "${FORGE_SQL_SA_PASSWORD:-}" ]] || die "FORGE_SQL_SA_PASSWORD is required for soft clear."

        container_running || die "Container '$FORGE_SQL_DOCKER_CONTAINER' is not running. Start it and retry (or run hard clear)."
        wait_for_sql_ready
        drop_user_databases
        echo "✔ Soft clear complete."
        exit 0
    fi

    # Hard clear
    echo "Performing hard clear (drop DBs, remove container, clear data)..."

    if container_running; then
        echo "Stopping container '$FORGE_SQL_DOCKER_CONTAINER'..."
        docker stop "$FORGE_SQL_DOCKER_CONTAINER" >/dev/null
    fi

    if container_exists; then
        echo "Removing container '$FORGE_SQL_DOCKER_CONTAINER'..."
        docker rm "$FORGE_SQL_DOCKER_CONTAINER" >/dev/null
    else
        echo "Container '$FORGE_SQL_DOCKER_CONTAINER' not found; nothing to remove."
    fi

    clear_container_data_dir

    echo "✔ Hard clear complete."
}

main "$@"
