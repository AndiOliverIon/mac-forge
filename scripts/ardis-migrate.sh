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

# Required variables
: "${ARDIS_MIGRATIONS_PATH:?ARDIS_MIGRATIONS_PATH must be set in forge.sh}"
: "${ARDIS_MIGRATIONS_LIBRARY:?ARDIS_MIGRATIONS_LIBRARY must be set in forge.sh}"
: "${FORGE_SQL_DOCKER_CONTAINER:?FORGE_SQL_DOCKER_CONTAINER must be set in forge.sh}"
: "${FORGE_SQL_USER:?FORGE_SQL_USER must be set (probably in forge-secrets.sh)}"
: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set (probably in forge-secrets.sh)}"

# Host & port to connect from the migration console (container exposed to host)
FORGE_SQL_HOST="${FORGE_SQL_HOST:-localhost}"
FORGE_SQL_PORT="${FORGE_SQL_PORT:-1433}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required but not found in PATH." >&2
    exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required but not found in PATH." >&2
    exit 1
fi

if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet is required but not found in PATH." >&2
    exit 1
fi

#######################################
# Helper: ensure SQL container is running
#######################################
ensure_container_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"; then
        echo "SQL container '$FORGE_SQL_DOCKER_CONTAINER' is not running. Start it and retry." >&2
        exit 1
    fi
}

#######################################
# Helper: detect TargetFramework from .csproj
#######################################
detect_target_framework() {
    local csproj="$1"
    local tfm tfms

    # Try <TargetFramework>
    tfm="$(sed -n 's/.*<TargetFramework>\(.*\)<\/TargetFramework>.*/\1/p' "$csproj" | head -n1)"

    if [[ -n "$tfm" ]]; then
        printf '%s\n' "$tfm"
        return 0
    fi

    # Try <TargetFrameworks> (multi-target; pick the first)
    tfms="$(sed -n 's/.*<TargetFrameworks>\(.*\)<\/TargetFrameworks>.*/\1/p' "$csproj" | head -n1)"
    if [[ -n "$tfms" ]]; then
        tfm="${tfms%%;*}"
        printf '%s\n' "$tfm"
        return 0
    fi

    return 1
}

#######################################
# Helper: list databases from container
#######################################
list_databases() {
    sqlcmd \
        -S "${FORGE_SQL_HOST},${FORGE_SQL_PORT}" \
        -U "$FORGE_SQL_USER" \
        -P "$FORGE_SQL_SA_PASSWORD" \
        -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;" \
        -h -1 -W 2>/dev/null | tr -d '\r' || return 1
}


#######################################
# Helper: let user choose DB via fzf
#######################################
choose_database() {
    local dbs selected

    # log to stderr, not stdout
    echo "Querying databases from container '$FORGE_SQL_DOCKER_CONTAINER'..." >&2
    dbs="$(list_databases)"
    if [[ -z "${dbs// }" ]]; then
        echo "No user databases found (or query failed)." >&2
        return 1
    fi

    selected="$(printf '%s\n' "$dbs" | fzf --prompt='Select database to migrate: ' --height=20 --border)"
    if [[ -z "${selected:-}" ]]; then
        echo "No database selected. Aborting." >&2
        return 1
    fi

    # ONLY the DB name to stdout
    printf '%s\n' "$selected"
}


#######################################
# Main
#######################################
main() {
    local csproj tfm bin_dir db conn_str

    # ARDIS_MIGRATIONS_PATH is the *project root*
    csproj="$ARDIS_MIGRATIONS_PATH/Ardis.Migrations.Console.csproj"
    if [[ ! -f "$csproj" ]]; then
        echo "csproj not found at $csproj" >&2
        exit 1
    fi

    echo "Detecting TargetFramework from $csproj..."
    if ! tfm="$(detect_target_framework "$csproj")"; then
        echo "Could not detect TargetFramework from $csproj" >&2
        exit 1
    fi
    echo "TargetFramework: $tfm"

    echo "Building migrations project..."
    (
        cd "$ARDIS_MIGRATIONS_PATH"
        dotnet build "$csproj" --configuration Debug
    )

    bin_dir="$ARDIS_MIGRATIONS_PATH/bin/Debug/$tfm"

    if [[ ! -d "$bin_dir" ]]; then
        echo "Build output folder not found: $bin_dir" >&2
        exit 1
    fi

    echo "Build output: $bin_dir"

    if ! command -v sqlcmd >/dev/null 2>&1; then
        echo "sqlcmd is required but not found in PATH. Install with: brew install sqlcmd" >&2
        exit 1
    fi

    # Choose database
    ensure_container_running
    db="$(choose_database)" || exit 1
    echo "Selected database: $db"

    # Compose connection string for the console (from host to container)
    conn_str="Server=${FORGE_SQL_HOST},${FORGE_SQL_PORT};Database=${db};User ID=${FORGE_SQL_USER};Password=${FORGE_SQL_SA_PASSWORD};TrustServerCertificate=True;Encrypt=False;"

    export MIGRATIONS_DatabaseConnectionString="$conn_str"

    echo "Using MIGRATIONS_DatabaseConnectionString (password hidden):"
    echo "  Server=${FORGE_SQL_HOST},${FORGE_SQL_PORT};Database=${db};User ID=${FORGE_SQL_USER};Password=********;TrustServerCertificate=True;Encrypt=False;"
    echo

    echo "Running migrations from: $bin_dir/$ARDIS_MIGRATIONS_LIBRARY"
    (
        cd "$bin_dir"
        dotnet "$ARDIS_MIGRATIONS_LIBRARY" --v --logs --demo
    )
}

main "$@"
