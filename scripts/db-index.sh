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
die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }
log_step() { echo "-> $*"; }

load_secrets() {
  if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$FORGE_SECRETS_FILE"
  fi
}

usage() {
  cat <<'USAGE'
Usage: db-index.sh [--server VERSION_OR_TAG]

Rebuild all indexes in a selected ONLINE local Docker SQL database.

Options:
  --server 2022        Use the forge-sql-2022 target.
  --server 2019        Use the forge-sql-2019 target.
  --server 2019-latest Use a specific mssql/server tag target suffix.

Default behavior uses the existing forge-sql container.
USAGE
}

sql_server_image_tag() {
  local image="$1"
  printf '%s\n' "${image##*:}"
}

sql_server_target_suffix() {
  local image="$1"
  local tag suffix

  tag="$(sql_server_image_tag "$image")"

  case "$tag" in
    2017-latest|2019-latest|2022-latest|2025-latest)
      printf '%s\n' "${tag%%-*}"
      ;;
    *)
      suffix="$(printf '%s\n' "$tag" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
      [[ -n "$suffix" ]] || suffix="custom"
      printf '%s\n' "$suffix"
      ;;
  esac
}

resolve_sql_server_image() {
  local server="$1"

  case "$server" in
    mcr.microsoft.com/mssql/server:*)
      printf '%s\n' "$server"
      ;;
    *:*)
      printf '%s\n' "$server"
      ;;
    2017|2019|2022|2025)
      printf 'mcr.microsoft.com/mssql/server:%s-latest\n' "$server"
      ;;
    *)
      printf 'mcr.microsoft.com/mssql/server:%s\n' "$server"
      ;;
  esac
}

configure_index_target() {
  local image="$1"
  local suffix

  FORGE_INDEX_SQL_CONTAINER="$FORGE_SQL_DOCKER_CONTAINER"

  if [[ "$image" == "$FORGE_SQL_DOCKER_IMAGE" ]]; then
    return 0
  fi

  suffix="$(sql_server_target_suffix "$image")"
  FORGE_INDEX_SQL_CONTAINER="${FORGE_SQL_DOCKER_CONTAINER}-${suffix}"
}

parse_args() {
  local index_image="$FORGE_SQL_DOCKER_IMAGE"

  while (($# > 0)); do
    case "$1" in
      --server)
        shift
        [[ $# -gt 0 && -n "$1" ]] || die "--server requires a version or tag."
        index_image="$(resolve_sql_server_image "$1")"
        ;;
      --server=*)
        local server="${1#--server=}"
        [[ -n "$server" ]] || die "--server requires a version or tag."
        index_image="$(resolve_sql_server_image "$server")"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done

  configure_index_target "$index_image"
}

ensure_sql_container_running() {
  : "${FORGE_INDEX_SQL_CONTAINER:?FORGE_INDEX_SQL_CONTAINER must be set}"

  if ! docker ps -a --format '{{.Names}}' | grep -q "^${FORGE_INDEX_SQL_CONTAINER}$"; then
    die "SQL container '$FORGE_INDEX_SQL_CONTAINER' does not exist. Restore/start that server target first."
  fi

  if docker ps --format '{{.Names}}' | grep -q "^${FORGE_INDEX_SQL_CONTAINER}$"; then
    log_step "Container '$FORGE_INDEX_SQL_CONTAINER' is already running."
  else
    log_step "Starting container '$FORGE_INDEX_SQL_CONTAINER'..."
    docker start "$FORGE_INDEX_SQL_CONTAINER" >/dev/null
  fi
}

wait_for_sql_ready() {
  local max_tries=30
  local i

  log_step "Waiting for SQL Server in container '$FORGE_INDEX_SQL_CONTAINER'..."
  for ((i = 1; i <= max_tries; i++)); do
    if docker exec "$FORGE_INDEX_SQL_CONTAINER" \
      /opt/mssql-tools18/bin/sqlcmd \
      -S localhost -U "$FORGE_SQL_USER" -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
      -Q "SELECT 1" >/dev/null 2>&1; then
      log_step "SQL Server is ready (attempt $i)."
      return 0
    fi
    sleep 2
  done

  die "SQL Server did not become ready."
}

sqlcmd_container() {
  docker exec -i "$FORGE_INDEX_SQL_CONTAINER" \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U "$FORGE_SQL_USER" -P "$FORGE_SQL_SA_PASSWORD" -C "$@"
}

list_databases() {
  sqlcmd_container -d master -h -1 -W -Q "
SET NOCOUNT ON;
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = 'ONLINE'
ORDER BY name;
" 2>/dev/null | tr -d '\r' | sed '/^$/d'
}

choose_database() {
  local dbs selected

  log_step "Retrieving ONLINE user databases from '$FORGE_INDEX_SQL_CONTAINER'..." >&2
  dbs="$(list_databases || true)"
  [[ -n "${dbs// /}" ]] || die "No ONLINE user databases found."

  selected="$(printf '%s\n' "$dbs" | fzf --prompt='Rebuild indexes in database > ' --height=40% --border)" \
    || die "No database selected."
  [[ -n "${selected:-}" ]] || die "No database selected."
  printf '%s\n' "$selected"
}

rebuild_indexes() {
  local db="$1"

  sqlcmd_container -b -d "$db" <<'SQL_EOF'
SET NOCOUNT ON;

DECLARE
  @schema sysname,
  @object sysname,
  @sql nvarchar(max),
  @rebuilt int = 0,
  @failures int = 0;

DECLARE index_objects CURSOR LOCAL FAST_FORWARD FOR
  SELECT s.name, o.name
  FROM sys.objects o
  JOIN sys.schemas s ON s.schema_id = o.schema_id
  WHERE o.type IN ('U', 'V')
    AND EXISTS (
      SELECT 1
      FROM sys.indexes i
      WHERE i.object_id = o.object_id
        AND i.index_id > 0
        AND i.is_hypothetical = 0
    )
  ORDER BY s.name, o.name;

OPEN index_objects;
FETCH NEXT FROM index_objects INTO @schema, @object;

WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    SET @sql = N'ALTER INDEX ALL ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@object) + N' REBUILD;';
    PRINT N'Rebuilding indexes on ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@object);
    EXEC sys.sp_executesql @sql;
    SET @rebuilt += 1;
  END TRY
  BEGIN CATCH
    SET @failures += 1;
    PRINT N'[failed] ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@object) + N': ' + ERROR_MESSAGE();
  END CATCH;

  FETCH NEXT FROM index_objects INTO @schema, @object;
END;

CLOSE index_objects;
DEALLOCATE index_objects;

PRINT CONCAT('Index rebuild complete. Objects rebuilt: ', @rebuilt, '. Failures: ', @failures, '.');

IF @failures > 0
  THROW 51000, 'One or more index rebuild operations failed.', 1;
SQL_EOF
}

#######################################
# Main
#######################################
require_cmd docker
require_cmd fzf
load_secrets

: "${FORGE_SQL_USER:?FORGE_SQL_USER must be set in forge.sh}"
: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set (probably in forge-secrets.sh)}"

parse_args "$@"
ensure_sql_container_running
wait_for_sql_ready

DB_NAME="$(choose_database)"

echo
echo "Container: $FORGE_INDEX_SQL_CONTAINER"
echo "Database : $DB_NAME"
echo "Action   : rebuild all indexes on indexed tables/views"
echo
read -r -p "Proceed with rebuilding all indexes in [$DB_NAME]? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || die "Aborted (no changes made)."

log_step "Rebuilding indexes in [$DB_NAME]..."
rebuild_indexes "$DB_NAME"
echo "OK: Index rebuild completed for [$DB_NAME]."
