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

load_secrets() {
  if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$FORGE_SECRETS_FILE"
  fi
}

log_step() { echo "-> $*"; }

#######################################
# Wait for SQL Server readiness
#######################################
wait_for_sql_ready() {
  local max_tries=30
  local i
  log_step "Waiting for SQL Server in container '$FORGE_SQL_DOCKER_CONTAINER'..."

  for ((i = 1; i <= max_tries; i++)); do
    if docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
      /opt/mssql-tools18/bin/sqlcmd \
      -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
      -Q "SELECT 1" >/dev/null 2>&1; then
      log_step "SQL Server is ready (attempt $i)."
      return 0
    fi
    sleep 2
  done

  die "SQL Server did not become ready."
}

#######################################
# Ensure SQL container exists & is running
#
# Container data mount depends on last saved work state:
#   - internal  => /var/opt/mssql is a NAMED VOLUME (internal to Docker)
#   - external  => /var/opt/mssql is a BIND mount (host path: FORGE_SQL_DATA_BIND_PATH)
#
# Snapshots is ALWAYS a bind mount from host (FORGE_SQL_SNAPSHOTS_PATH)
#######################################
ensure_sql_container() {
  require_cmd docker
  load_secrets

  : "${FORGE_SQL_DOCKER_CONTAINER:?FORGE_SQL_DOCKER_CONTAINER must be set in forge.sh}"
  : "${FORGE_SQL_DOCKER_IMAGE:?FORGE_SQL_DOCKER_IMAGE must be set in forge.sh}"
  : "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set in forge-secrets.sh}"
  : "${FORGE_SQL_SNAPSHOTS_PATH:?FORGE_SQL_SNAPSHOTS_PATH must be set in forge.sh}"
  : "${FORGE_SQL_DOCKER_SNAPSHOTS_PATH:?FORGE_SQL_DOCKER_SNAPSHOTS_PATH must be set in forge.sh}"
  : "${FORGE_SQL_DOCKER_ROOT:?FORGE_SQL_DOCKER_ROOT must be set in forge.sh}"
  : "${FORGE_SQL_DATA_VOLUME_NAME:?FORGE_SQL_DATA_VOLUME_NAME must be set in forge.sh}"
  : "${FORGE_SQL_DATA_MOUNT_KIND:?FORGE_SQL_DATA_MOUNT_KIND must be set in forge.sh}"

  local name="$FORGE_SQL_DOCKER_CONTAINER"
  local image="$FORGE_SQL_DOCKER_IMAGE"
  local host_port="${FORGE_SQL_PORT:-1433}"

  # Snapshots dir must exist on host
  mkdir -p "$FORGE_SQL_SNAPSHOTS_PATH"
  [[ -d "$FORGE_SQL_SNAPSHOTS_PATH" && -w "$FORGE_SQL_SNAPSHOTS_PATH" ]] || \
    die "Snapshots path not writable on host: $FORGE_SQL_SNAPSHOTS_PATH"

  local data_mount_arg=""
  if [[ "$FORGE_SQL_DATA_MOUNT_KIND" == "bind" ]]; then
    : "${FORGE_SQL_DATA_BIND_PATH:?FORGE_SQL_DATA_BIND_PATH must be set for external container mode}"
    mkdir -p "$FORGE_SQL_DATA_BIND_PATH"
    [[ -d "$FORGE_SQL_DATA_BIND_PATH" && -w "$FORGE_SQL_DATA_BIND_PATH" ]] || \
      die "SQL data bind path not writable on host: $FORGE_SQL_DATA_BIND_PATH"
    data_mount_arg="-v ${FORGE_SQL_DATA_BIND_PATH}:${FORGE_SQL_DOCKER_ROOT}"
  else
    # Ensure named volume exists
    docker volume inspect "$FORGE_SQL_DATA_VOLUME_NAME" >/dev/null 2>&1 || \
      docker volume create "$FORGE_SQL_DATA_VOLUME_NAME" >/dev/null
    data_mount_arg="-v ${FORGE_SQL_DATA_VOLUME_NAME}:${FORGE_SQL_DOCKER_ROOT}"
  fi

  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
      log_step "Container '$name' is already running."
    else
      log_step "Starting container '$name'..."
      docker start "$name" >/dev/null
    fi
  else
    log_step "Creating SQL Server container '$name'..."
    docker run -d \
      --name "$name" \
      -e "ACCEPT_EULA=Y" \
      -e "MSSQL_SA_PASSWORD=$FORGE_SQL_SA_PASSWORD" \
      -e "SA_PASSWORD=$FORGE_SQL_SA_PASSWORD" \
      -p "${host_port}:1433" \
      $data_mount_arg \
      -v "${FORGE_SQL_SNAPSHOTS_PATH}:${FORGE_SQL_DOCKER_SNAPSHOTS_PATH}" \
      "$image" >/dev/null
  fi
}

#######################################
# Find .bak files (maxdepth 1)
# (maxdepth 1)
#######################################
find_baks_in_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0

  find "$dir" \
    -maxdepth 1 \
    -type f \
    -iname "*.bak" \
    ! -name '._*' \
    -print 2>/dev/null
}

#######################################
# Preconditions
#######################################
require_cmd docker
require_cmd fzf
load_secrets

ensure_sql_container
wait_for_sql_ready

#######################################
# Ensure snapshots folder exists + writable in container
#######################################
docker exec -u 0 "$FORGE_SQL_DOCKER_CONTAINER" /bin/bash -lc "
  mkdir -p '$FORGE_SQL_DOCKER_SNAPSHOTS_PATH' &&
  chown -R mssql:mssql '$FORGE_SQL_DOCKER_SNAPSHOTS_PATH' 2>/dev/null || true &&
  chmod 775 '$FORGE_SQL_DOCKER_SNAPSHOTS_PATH' 2>/dev/null || true
" >/dev/null || die "Failed to prepare snapshots folder in container: $FORGE_SQL_DOCKER_SNAPSHOTS_PATH"

#######################################
# Candidate backups: current dir + snapshots dir
#######################################
CWD="$(pwd)"
candidates=()

mapfile -t cwd_baks < <(find_baks_in_dir "$CWD" || true)
mapfile -t snap_baks < <(find_baks_in_dir "$FORGE_SQL_SNAPSHOTS_PATH" || true)

# Merge + de-dupe
declare -A seen=()
for f in "${cwd_baks[@]}" "${snap_baks[@]}"; do
  [[ -n "$f" ]] || continue
  if [[ -z "${seen[$f]+x}" ]]; then
    seen["$f"]=1
    candidates+=("$f")
  fi
done

((${#candidates[@]} > 0)) || die "No .bak files found in: $CWD or $FORGE_SQL_SNAPSHOTS_PATH"

selected_file="$(
  printf '%s\n' "${candidates[@]}" | fzf --prompt='Select .bak to restore > '
)" || die "No file selected."

backup_basename="$(basename "$selected_file")"

#######################################
# Derive default DB name from filename
#######################################
base="${backup_basename%.*}"  # remove extension
base="${base%%.*}"            # cut at first dot
default_db_name="${base%%_*}" # cut at first underscore
[[ -n "$default_db_name" ]] || default_db_name="$base"

echo "Selected: $backup_basename"
read -r -p "Database name to restore into [$default_db_name]: " db_name
db_name="${db_name:-$default_db_name}"
[[ -n "$db_name" ]] || die "Database name cannot be empty."

#######################################
# Stage into snapshots as <db_name>.bak
#######################################
snapshot_filename="$db_name.bak"
snapshot_host_path="$FORGE_SQL_SNAPSHOTS_PATH/$snapshot_filename"
snapshot_container_path="$FORGE_SQL_DOCKER_SNAPSHOTS_PATH/$snapshot_filename"

if [[ "$selected_file" != "$snapshot_host_path" ]]; then
  log_step "Staging -> $snapshot_host_path"
  cp -f "$selected_file" "$snapshot_host_path"
fi

# Ensure container can read the staged file
docker exec -u 0 "$FORGE_SQL_DOCKER_CONTAINER" /bin/bash -lc "
  chown mssql:mssql '$snapshot_container_path' 2>/dev/null || true
  chmod 660 '$snapshot_container_path' 2>/dev/null || true
" >/dev/null || true

[[ -f "$snapshot_host_path" ]] || die "Snapshot not found on host: $snapshot_host_path"

#######################################
# Generate WITH MOVE from FILELISTONLY
#######################################
SQL_DATA_DIR="/var/opt/mssql/data"

filelist_csv="$(
  docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
    -r 1 -W -h -1 -s '|' -w 65535 <<SQL_EOF
SET NOCOUNT ON;
RESTORE FILELISTONLY
FROM DISK = N'$snapshot_container_path';
SQL_EOF
)" || die "Failed to read FILELISTONLY from backup."

if [[ -z "${filelist_csv//$'\n'/}" ]]; then
  die "FILELISTONLY returned no output. Check container access to: $snapshot_container_path"
fi

move_clauses="$(
  echo "$filelist_csv" | awk -F'|' -v db="$db_name" -v dir="$SQL_DATA_DIR" '
    function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
    BEGIN { d=0; l=0; }
    {
      if (NF < 2) next
      logical = trim($1)

      type = ""
      for (i=1; i<=NF; i++) {
        f = trim($i)
        if (f == "D" || f == "L") { type = f; break }
      }

      if (logical == "" || type == "") next

      if (type == "D") {
        d++
        suffix = (d == 1 ? "" : "_" d)
        target = dir "/" db suffix ".mdf"
        printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target)
      } else if (type == "L") {
        l++
        suffix = (l == 1 ? "" : "_" l)
        target = dir "/" db "_log" suffix ".ldf"
        printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target)
      }
    }
  ' | sed '$ s/,$//'
)"

[[ -n "$move_clauses" ]] || die "Could not generate MOVE clauses."

#######################################
# Restore
#######################################
log_step "Restoring [$db_name] from: $snapshot_container_path"

docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
  /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
  -b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
  IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
  BEGIN
    DECLARE @state nvarchar(60) = (SELECT state_desc FROM sys.databases WHERE name = N'$db_name');

    IF @state = N'RESTORING'
    BEGIN
      -- If a previous restore was interrupted, the DB can be left in RESTORING.
      -- Bring it online so we can safely replace it.
      BEGIN TRY
        RESTORE DATABASE [$db_name] WITH RECOVERY;
      END TRY
      BEGIN CATCH
        -- If recovery isn't possible (no restore chain), drop and continue with fresh restore.
        DROP DATABASE [$db_name];
      END CATCH
    END;

    ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  END;

  RESTORE DATABASE [$db_name]
  FROM DISK = N'$snapshot_container_path'
  WITH
    REPLACE,
    RECOVERY,
    $move_clauses;

  ALTER DATABASE [$db_name] SET MULTI_USER;
END TRY
BEGIN CATCH
  DECLARE
    @num int = ERROR_NUMBER(),
    @sev int = ERROR_SEVERITY(),
    @st  int = ERROR_STATE(),
    @ln  int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('RESTORE FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH

SQL_EOF

echo "OK: Database [$db_name] restored."
echo "Snapshot: $snapshot_host_path"
