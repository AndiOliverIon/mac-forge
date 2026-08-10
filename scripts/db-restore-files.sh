#!/opt/homebrew/bin/bash
set -euo pipefail

# db-restore-files.sh (alias: dbrf)
#
# Experimental sibling of db-restore.sh (dbr). Instead of restoring from a .bak,
# this attaches a database directly from provided .mdf (+ optional .ldf) files.
#
# Flow mirrors dbr: it looks for .mdf files in the current dir and the snapshots
# dir, proposes a database name extracted from the .mdf filename, lets you accept
# or override it, then yields the restored (attached) database in the forge SQL
# Server container. The trailing "f" in the alias marks it as file-based.

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

usage() {
  cat <<'USAGE'
Usage: db-restore-files.sh [--server VERSION_OR_TAG]

Attach a database from an .mdf (+ optional matching .ldf) file.

Options:
  --server 2022        Use mcr.microsoft.com/mssql/server:2022-latest.
  --server 2019        Use mcr.microsoft.com/mssql/server:2019-latest.
  --server 2019-latest Use a specific mssql/server tag.

Default behavior keeps using the existing forge-sql container.
Non-default server versions use a parallel container and data path.

Common SQL Server Docker versions:
  2025, 2022, 2019, 2017

Full tag list:
  https://mcr.microsoft.com/v2/mssql/server/tags/list
USAGE
}

known_sql_server_versions() {
  cat <<'EOF'
Common SQL Server Docker versions:
  --server 2025
  --server 2022
  --server 2019
  --server 2017

You can also pass a full mssql/server tag, for example:
  --server 2019-latest
  --server 2022-CU14-ubuntu-22.04

Full tag list:
  https://mcr.microsoft.com/v2/mssql/server/tags/list
EOF
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

sql_server_host_port() {
  local suffix="$1"
  local checksum

  if [[ "$suffix" =~ ^(2017|2019|2022|2025)$ ]]; then
    printf '%s\n' "$suffix"
    return 0
  fi

  checksum="$(printf '%s\n' "$suffix" | cksum | awk '{print $1}')"
  printf '%s\n' "$((21000 + (checksum % 1000)))"
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

configure_restore_target() {
  local image="$1"
  local suffix

  FORGE_RESTORE_SQL_CONTAINER="$FORGE_SQL_DOCKER_CONTAINER"
  FORGE_RESTORE_SQL_DATA_BIND_PATH="$FORGE_SQL_DATA_BIND_PATH"
  FORGE_RESTORE_SQL_DATA_VOLUME_NAME="$FORGE_SQL_DATA_VOLUME_NAME"
  FORGE_RESTORE_SQL_PORT="${FORGE_SQL_PORT:-1433}"

  if [[ "$image" == "$FORGE_SQL_DOCKER_IMAGE" ]]; then
    return 0
  fi

  suffix="$(sql_server_target_suffix "$image")"
  FORGE_RESTORE_SQL_CONTAINER="${FORGE_SQL_DOCKER_CONTAINER}-${suffix}"
  FORGE_RESTORE_SQL_DATA_BIND_PATH="${FORGE_SQL_DATA_BIND_PATH}-${suffix}"
  FORGE_RESTORE_SQL_DATA_VOLUME_NAME="${FORGE_SQL_DATA_VOLUME_NAME}-${suffix}"
  FORGE_RESTORE_SQL_PORT="$(sql_server_host_port "$suffix")"
}

verify_sql_server_image() {
  local image="$1"

  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  if docker manifest inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: SQL Server Docker image was not found or could not be verified: $image" >&2
  echo >&2
  known_sql_server_versions >&2
  exit 1
}

parse_args() {
  FORGE_RESTORE_SQL_IMAGE="$FORGE_SQL_DOCKER_IMAGE"
  FORGE_RESTORE_SQL_SERVER_REQUESTED=0

  while (($# > 0)); do
    case "$1" in
      --server)
        shift
        [[ $# -gt 0 ]] || die "--server requires a version or tag."
        [[ -n "$1" ]] || die "--server requires a version or tag."
        FORGE_RESTORE_SQL_IMAGE="$(resolve_sql_server_image "$1")"
        FORGE_RESTORE_SQL_SERVER_REQUESTED=1
        ;;
      --server=*)
        local server="${1#--server=}"
        [[ -n "$server" ]] || die "--server requires a version or tag."
        FORGE_RESTORE_SQL_IMAGE="$(resolve_sql_server_image "$server")"
        FORGE_RESTORE_SQL_SERVER_REQUESTED=1
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

  configure_restore_target "$FORGE_RESTORE_SQL_IMAGE"

  FORGE_SQL_DOCKER_IMAGE="$FORGE_RESTORE_SQL_IMAGE"
  FORGE_SQL_DOCKER_CONTAINER="$FORGE_RESTORE_SQL_CONTAINER"
  FORGE_SQL_DATA_BIND_PATH="$FORGE_RESTORE_SQL_DATA_BIND_PATH"
  FORGE_SQL_DATA_VOLUME_NAME="$FORGE_RESTORE_SQL_DATA_VOLUME_NAME"
  FORGE_SQL_PORT="$FORGE_RESTORE_SQL_PORT"
}

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

  local name="${FORGE_RESTORE_SQL_CONTAINER:-$FORGE_SQL_DOCKER_CONTAINER}"
  local image="${FORGE_RESTORE_SQL_IMAGE:-$FORGE_SQL_DOCKER_IMAGE}"
  local host_port="${FORGE_RESTORE_SQL_PORT:-${FORGE_SQL_PORT:-1433}}"
  local data_bind_path="${FORGE_RESTORE_SQL_DATA_BIND_PATH:-$FORGE_SQL_DATA_BIND_PATH}"
  local existing_image

  # Snapshots dir must exist on host
  mkdir -p "$FORGE_SQL_SNAPSHOTS_PATH"
  [[ -d "$FORGE_SQL_SNAPSHOTS_PATH" && -w "$FORGE_SQL_SNAPSHOTS_PATH" ]] || \
    die "Snapshots path not writable on host: $FORGE_SQL_SNAPSHOTS_PATH"

  local data_mount_arg=""
  if [[ "$FORGE_SQL_DATA_MOUNT_KIND" == "bind" ]]; then
    : "${data_bind_path:?FORGE_SQL_DATA_BIND_PATH must be set for external container mode}"
    mkdir -p "$data_bind_path"
    [[ -d "$data_bind_path" && -w "$data_bind_path" ]] || \
      die "SQL data bind path not writable on host: $data_bind_path"
    data_mount_arg="-v ${data_bind_path}:${FORGE_SQL_DOCKER_ROOT}"
  else
    docker volume inspect "$FORGE_SQL_DATA_VOLUME_NAME" >/dev/null 2>&1 || \
      docker volume create "$FORGE_SQL_DATA_VOLUME_NAME" >/dev/null
    data_mount_arg="-v ${FORGE_SQL_DATA_VOLUME_NAME}:${FORGE_SQL_DOCKER_ROOT}"
  fi

  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    if [[ "${FORGE_RESTORE_SQL_SERVER_REQUESTED:-0}" == "1" ]]; then
      existing_image="$(docker inspect --format '{{.Config.Image}}' "$name" 2>/dev/null || true)"
      if [[ "$existing_image" != "$image" ]]; then
        die "Container '$name' already exists with image '$existing_image', but --server requested '$image'. Remove that container to recreate it, or choose the existing server version."
      fi
    fi

    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
      log_step "Container '$name' is already running."
    else
      log_step "Starting container '$name'..."
      docker start "$name" >/dev/null
    fi
  else
    log_step "Creating SQL Server container '$name' with image '$image' on host port '$host_port'..."
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
# Find .mdf files (maxdepth 1)
#######################################
find_mdfs_in_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0

  find "$dir" \
    -maxdepth 1 \
    -type f \
    -iname "*.mdf" \
    ! -name '._*' \
    -print 2>/dev/null
}

#######################################
# Find the .ldf that pairs with a selected .mdf (maxdepth 1, same dir)
# Preference: <base>_log.ldf, then <base>.ldf, then any single .ldf, else none.
#######################################
find_matching_ldf() {
  local mdf="$1"
  local dir base cand

  dir="$(cd "$(dirname "$mdf")" && pwd)"
  base="$(basename "$mdf")"
  base="${base%.*}"

  for cand in "$dir/${base}_log.ldf" "$dir/${base}_Log.ldf" "$dir/${base}.ldf"; do
    if [[ -f "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done

  # Fallback: if exactly one .ldf exists in the dir, pair it.
  local ldfs=()
  mapfile -t ldfs < <(find "$dir" -maxdepth 1 -type f -iname "*.ldf" ! -name '._*' -print 2>/dev/null)
  if ((${#ldfs[@]} == 1)); then
    printf '%s\n' "${ldfs[0]}"
    return 0
  fi

  return 0
}

#######################################
# Preconditions
#######################################
parse_args "$@"

require_cmd docker
require_cmd fzf
load_secrets

if [[ "${FORGE_RESTORE_SQL_SERVER_REQUESTED:-0}" == "1" ]]; then
  verify_sql_server_image "$FORGE_RESTORE_SQL_IMAGE"
fi

ensure_sql_container
wait_for_sql_ready

#######################################
# Candidate .mdf files: current dir + snapshots dir
#######################################
CWD="$(pwd)"
candidates=()

mapfile -t cwd_mdfs < <(find_mdfs_in_dir "$CWD" || true)
mapfile -t snap_mdfs < <(find_mdfs_in_dir "$FORGE_SQL_SNAPSHOTS_PATH" || true)

declare -A seen=()
for f in "${cwd_mdfs[@]}" "${snap_mdfs[@]}"; do
  [[ -n "$f" ]] || continue
  if [[ -z "${seen[$f]+x}" ]]; then
    seen["$f"]=1
    candidates+=("$f")
  fi
done

((${#candidates[@]} > 0)) || die "No .mdf files found in: $CWD or $FORGE_SQL_SNAPSHOTS_PATH"

selected_mdf="$(
  printf '%s\n' "${candidates[@]}" | fzf --prompt='Select .mdf to attach > '
)" || die "No file selected."

[[ -f "$selected_mdf" ]] || die "Selected .mdf not found: $selected_mdf"

selected_ldf="$(find_matching_ldf "$selected_mdf")"

mdf_basename="$(basename "$selected_mdf")"
if [[ -n "$selected_ldf" ]]; then
  echo "Selected: $mdf_basename (+ log: $(basename "$selected_ldf"))"
else
  echo "Selected: $mdf_basename (no matching .ldf found; log will be rebuilt)"
fi

#######################################
# Derive default DB name from filename
#######################################
base="${mdf_basename%.*}"     # remove extension
base="${base%%.*}"            # cut at first dot
base="${base%_Data}"          # drop trailing _Data if present
base="${base%_data}"
default_db_name="${base%%_*}" # cut at first underscore
[[ -n "$default_db_name" ]] || default_db_name="$base"

read -r -p "Database name to attach into [$default_db_name]: " db_name
db_name="${db_name:-$default_db_name}"
[[ -n "$db_name" ]] || die "Database name cannot be empty."

#######################################
# Target physical paths inside the container
#######################################
SQL_DATA_DIR="/var/opt/mssql/data"
target_mdf="$SQL_DATA_DIR/${db_name}.mdf"
target_ldf="$SQL_DATA_DIR/${db_name}_log.ldf"

#######################################
# Collision check: refuse if another database already owns the target files.
#######################################
conflict="$(
  docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
    -h -1 -W -b <<SQL_EOF
SET NOCOUNT ON;
SELECT TOP 1 DB_NAME(database_id)
FROM sys.master_files
WHERE physical_name IN (N'$target_mdf', N'$target_ldf')
  AND DB_NAME(database_id) <> N'$db_name';
SQL_EOF
)" || die "Failed to check for file conflicts in container."

conflict="$(printf '%s' "$conflict" | tr -d '\r' | sed '/^$/d' | head -n1)"
if [[ -n "$conflict" && "$conflict" != "NULL" ]]; then
  die "Target files are already owned by database '$conflict'. Choose a different name."
fi

#######################################
# Drop existing DB with the same name (frees its physical files)
#######################################
log_step "Preparing target database [$db_name]..."
docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
  /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
  -b <<SQL_EOF
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
BEGIN
  ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [$db_name];
END;
SQL_EOF

#######################################
# Copy files into the container data dir under the target name
#######################################
log_step "Staging data file -> $target_mdf"
docker cp "$selected_mdf" "$FORGE_SQL_DOCKER_CONTAINER:$target_mdf" >/dev/null \
  || die "Failed to copy .mdf into container."

if [[ -n "$selected_ldf" ]]; then
  log_step "Staging log file  -> $target_ldf"
  docker cp "$selected_ldf" "$FORGE_SQL_DOCKER_CONTAINER:$target_ldf" >/dev/null \
    || die "Failed to copy .ldf into container."
fi

docker exec -u 0 "$FORGE_SQL_DOCKER_CONTAINER" /bin/bash -lc "
  chown mssql:mssql '$target_mdf' 2>/dev/null || true
  chmod 660 '$target_mdf' 2>/dev/null || true
  if [[ -f '$target_ldf' ]]; then
    chown mssql:mssql '$target_ldf' 2>/dev/null || true
    chmod 660 '$target_ldf' 2>/dev/null || true
  fi
" >/dev/null || true

#######################################
# Attach
#######################################
if [[ -n "$selected_ldf" ]]; then
  attach_files="( FILENAME = N'$target_mdf' ),
  ( FILENAME = N'$target_ldf' )
  FOR ATTACH;"
else
  attach_files="( FILENAME = N'$target_mdf' )
  FOR ATTACH_REBUILD_LOG;"
fi

log_step "Attaching [$db_name] from: $target_mdf"

docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
  /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$FORGE_SQL_SA_PASSWORD" -C -d master \
  -b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
  CREATE DATABASE [$db_name]
  ON
  $attach_files

  ALTER DATABASE [$db_name] SET MULTI_USER;
END TRY
BEGIN CATCH
  DECLARE
    @num int = ERROR_NUMBER(),
    @sev int = ERROR_SEVERITY(),
    @st  int = ERROR_STATE(),
    @ln  int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('ATTACH FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH
SQL_EOF

echo "OK: Database [$db_name] attached."
echo "Data file: $target_mdf"
[[ -n "$selected_ldf" ]] && echo "Log file:  $target_ldf"
