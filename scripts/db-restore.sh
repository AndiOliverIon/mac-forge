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

#######################################
# Load secrets from iCloud (if any)
#######################################
load_secrets() {
    if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$FORGE_SECRETS_FILE"
    fi
}

#######################################
# Ensure SQL container exists & is running
#######################################
ensure_sql_container() {
    require_cmd docker
    load_secrets

    # Prefer FORGE_SQL_SA_PASSWORD, fall back to SA_PASSWORD if set
    local sa_password="${FORGE_SQL_SA_PASSWORD:-${SA_PASSWORD:-}}"
    [[ -n "$sa_password" ]] || die "SA password not set. Define FORGE_SQL_SA_PASSWORD in '$FORGE_SECRETS_FILE'."

    local name="$FORGE_SQL_DOCKER_CONTAINER"
    local image="mcr.microsoft.com/mssql/server:2022-latest"  # adjust if needed

    # Does container exist at all?
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}\$"; then
        echo "Container '$name' already exists."

        # Is it running?
        if docker ps --format '{{.Names}}' | grep -q "^${name}\$"; then
            echo "Container '$name' is already running."
        else
            echo "Starting existing container '$name'..."
            docker start "$name" >/dev/null
        fi
    else
        echo "Container '$name' does not exist. Creating a new SQL Server container..."

        docker run -d \
            --name "$name" \
            -e "ACCEPT_EULA=Y" \
            -e "MSSQL_SA_PASSWORD=$sa_password" \
            -e "SA_PASSWORD=$sa_password" \
            -p 1433:1433 \
            "$image" >/dev/null

        echo "Container '$name' created and started from image '$image'."
    fi
}

#######################################
# Preconditions
#######################################
require_cmd fzf
require_cmd docker
ensure_sql_container


#######################################
# Step 1: Collect backup files
#######################################
load_backups() {
    local dir="$1"
    mapfile -d '' backups < <(
        find "$dir" -maxdepth 1 -type f -iname "*.bak" -print0 2>/dev/null
    )
}

# Try script directory first
load_backups "$SCRIPT_DIR"

# If none found, use FORGE_SQL_PATH
if (( ${#backups[@]} == 0 )); then
    echo "No backups found in script directory: $SCRIPT_DIR"
    echo "Falling back to: $FORGE_SQL_PATH"
    load_backups "$FORGE_SQL_PATH"
fi

(( ${#backups[@]} > 0 )) || die "No .bak files found in either location."


#######################################
# Step 2: Select backup via fzf
#######################################
backup_paths=("${backups[@]}")

selected_file="$(
    printf '%s\n' "${backup_paths[@]}" | fzf --prompt='Select backup to restore > '
)" || die "No file selected."

backup_basename="$(basename "$selected_file")"


#######################################
# Step 3: Extract default DB name
#######################################
base="${backup_basename%.*}"     # remove extension
base="${base%%.*}"               # cut at first dot
default_db_name="${base%%_*}"    # cut at first underscore

[[ -n "$default_db_name" ]] || default_db_name="$base"

echo "Selected backup: $backup_basename"
echo "Default DB name: $default_db_name"


#######################################
# Step 4: Confirm or override DB name
#######################################
read -r -p "Database name to restore into [$default_db_name]: " db_name
db_name="${db_name:-$default_db_name}"

[[ -n "$db_name" ]] || die "Database name cannot be empty."

container_backup_name="$db_name"

# ensure .bak extension
if [[ ! "$container_backup_name" =~ \.bak$ ]]; then
    container_backup_name="${container_backup_name}.bak"
fi


#######################################
# Step 5: Final sanity: container running
#######################################
if ! docker ps --format '{{.Names}}' | grep -q "^${FORGE_SQL_DOCKER_CONTAINER}\$"; then
    die "Container '$FORGE_SQL_DOCKER_CONTAINER' is not running even after ensure_sql_container."
fi


#######################################
# Step 6: Copy backup file into container (safe overwrite)
#######################################

# Ensure backup directory exists (as container default user)
docker exec "$FORGE_SQL_DOCKER_CONTAINER" bash -lc "
    mkdir -p '$FORGE_SQL_DOCKER_BACKUP_PATH'
"

# If file exists inside container → delete it first
docker exec "$FORGE_SQL_DOCKER_CONTAINER" bash -lc "
    if [ -f '$FORGE_SQL_DOCKER_BACKUP_PATH/$container_backup_name' ]; then
        echo 'Existing backup file found inside container, removing it...';
        rm -f '$FORGE_SQL_DOCKER_BACKUP_PATH/$container_backup_name';
    fi
"

# Copy new backup file into container
docker cp "$selected_file" \
    "${FORGE_SQL_DOCKER_CONTAINER}:${FORGE_SQL_DOCKER_BACKUP_PATH}/${container_backup_name}"

# Fix ownership and permissions as ROOT inside the container
docker exec -u 0 "$FORGE_SQL_DOCKER_CONTAINER" bash -lc "
    chown mssql:mssql '$FORGE_SQL_DOCKER_BACKUP_PATH/$container_backup_name' && \
    chmod 660 '$FORGE_SQL_DOCKER_BACKUP_PATH/$container_backup_name'
"

echo "✔ Copied backup into container (with overwrite handling) and adjusted permissions."

#######################################
# Step 7: Restore database
#######################################
echo "Starting restore of database [$db_name]..."

docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" bash -lc "
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \"\$SA_PASSWORD\" -C -b <<'SQL_EOF'
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
BEGIN
    PRINT 'Database $db_name exists → setting SINGLE_USER...';
    ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
END;

PRINT 'Restoring database $db_name...';

RESTORE DATABASE [$db_name]
FROM DISK = N'${FORGE_SQL_DOCKER_BACKUP_PATH}/${container_backup_name}'
WITH REPLACE, RECOVERY;

ALTER DATABASE [$db_name] SET MULTI_USER;
PRINT 'Restore completed successfully.';
SQL_EOF
"

echo "✅ Database [$db_name] restored successfully."
