#!/usr/bin/env bash
set -euo pipefail

# db-restore-files.sh (alias: dbrf)
#
# Experimental sibling of db-restore.sh (dbr). Instead of restoring from a .bak,
# this attaches a database directly from provided .mdf (+ optional .ldf) files.
#
# Flow mirrors dbr: pick a configured source path, select an .mdf, get a proposed
# database name extracted from the filename (accept or override), then yield the
# restored (attached) database in the forge SQL Server container. The trailing "f"
# in the alias marks it as file-based.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/forge.sh"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
else
  C_RESET=''
  C_BOLD=''
  C_BLUE=''
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
fi

print_line() {
  local color="$1"
  local icon="$2"
  shift 2
  printf '%s[%s]%s %s\n' "$color" "$icon" "$C_RESET" "$*"
}

section() {
  printf '\n%s%s%s\n' "$C_BLUE" "$1" "$C_RESET"
}

log_step() {
  print_line "$C_CYAN" '>' "$*"
}

log_info() {
  print_line "$C_BLUE" 'i' "$*"
}

log_warn() {
  print_line "$C_YELLOW" '!' "$*"
}

log_success() {
  print_line "$C_GREEN" '+' "$*"
}

die() {
  print_line "$C_RED" 'x' "$*" >&2
  exit 1
}

storage_fs_type() {
  local host_path="$1"

  if command -v findmnt >/dev/null 2>&1; then
    findmnt -no FSTYPE -T "$host_path" 2>/dev/null | head -n1
    return 0
  fi

  printf '\n'
}

sql_container_user() {
  local host_path="$1"
  local fs_type

  fs_type="$(storage_fs_type "$host_path")"

  case "$fs_type" in
      exfat|vfat|msdos|ntfs|ntfs3|fuseblk)
      printf '%s:0\n' "$(id -u)"
      ;;
    *)
      printf 'mssql\n'
      ;;
  esac
}

prepare_sql_bind_path() {
  local image="$1"
  local host_path="$2"
  local container_path="$3"
  local container_user="$4"

  log_step "Preparing SQL bind path permissions: $host_path"

  mkdir -p "$host_path"

  if [[ "$container_user" != "mssql" ]]; then
    return 0
  fi

  docker run --rm \
    -u 0 \
    -v "${host_path}:${container_path}" \
    --entrypoint /bin/bash \
    "$image" \
    -lc "
      mkdir -p '$container_path' &&
      chown -R 10001:0 '$container_path' &&
      find '$container_path' -type d -exec chmod 0770 {} \; &&
      find '$container_path' -type f -exec chmod 0660 {} \;
    " >/dev/null
}

show_container_failure_details() {
  local container_name="$1"

  if docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    echo
    echo "Container status:"
    docker ps -a --filter "name=^${container_name}$" --format '  {{.Names}}  {{.Status}}'
    echo
    echo "Recent container logs:"
    docker logs --tail 40 "$container_name" 2>&1 | sed 's/^/  /'
  fi
}

wait_for_sql_ready() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"
  local max_tries=30
  local i

  log_step "Waiting for SQL Server in container '$container_name'..."

  for ((i = 1; i <= max_tries; i++)); do
    if ! docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
      show_container_failure_details "$container_name"
      die "SQL Server container '$container_name' stopped before it became ready."
    fi

    if docker exec "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
      -Q "SELECT 1" >/dev/null 2>&1; then
      log_step "SQL Server is ready (attempt $i)."
      return 0
    fi
    sleep 2
  done

  show_container_failure_details "$container_name"
  die "SQL Server did not become ready."
}

ensure_sql_container() {
  local container_name="$1"
  local image="$2"
  local host_port="$3"
  local container_root="$4"
  local snapshots_host_path="$5"
  local snapshots_container_path="$6"
  local data_bind_path="$7"
  local sa_password="$8"
  local container_user="$9"
  local existing_user existing_data_mount existing_snapshots_mount

  mkdir -p "$snapshots_host_path" "$data_bind_path"
  forge_prepare_sql_shared_path "$snapshots_host_path"
  [[ -w "$snapshots_host_path" ]] || die "Snapshots path not writable: $snapshots_host_path"

  prepare_sql_bind_path "$image" "$data_bind_path" "$container_root" "$container_user"

  if docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    existing_user="$(docker inspect --format '{{.Config.User}}' "$container_name" 2>/dev/null || true)"
    existing_data_mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "'"$container_root"'"}}{{.Source}}{{end}}{{end}}' "$container_name" 2>/dev/null || true)"
    existing_snapshots_mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "'"$snapshots_container_path"'"}}{{.Source}}{{end}}{{end}}' "$container_name" 2>/dev/null || true)"

    if [[ "$existing_user" != "$container_user" || "$existing_data_mount" != "$data_bind_path" || "$existing_snapshots_mount" != "$snapshots_host_path" ]]; then
      if docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
        die "Container '$container_name' is running with a different user or mount configuration. Stop and remove it so dbrf can recreate it."
      fi

      log_step "Removing container '$container_name' to apply updated user/mount configuration..."
      docker rm "$container_name" >/dev/null
    fi
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    if docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
      log_step "Container '$container_name' is already running."
    else
      log_step "Starting container '$container_name'..."
      docker start "$container_name" >/dev/null
    fi
    return 0
  fi

  log_step "Creating SQL Server container '$container_name'..."
  docker run -d \
    --name "$container_name" \
    --user "$container_user" \
    -e "ACCEPT_EULA=Y" \
    -e "MSSQL_SA_PASSWORD=$sa_password" \
    -e "SA_PASSWORD=$sa_password" \
    -p "${host_port}:1433" \
    -v "${data_bind_path}:${container_root}" \
    -v "${snapshots_host_path}:${snapshots_container_path}" \
    "$image" >/dev/null
}

select_source_path() {
  local source_paths_json="$1"

  python3 - "$source_paths_json" <<'PY' | fzf --prompt='Data file source path > ' --height=40%
import json
import sys

for item in json.loads(sys.argv[1]):
    if isinstance(item, str) and item.strip():
        print(item)
PY
}

find_mdf_files() {
  local search_root="$1"
  [[ -d "$search_root" ]] || forge_die "Data file source path does not exist: $search_root"

  find "$search_root" -type f -iname "*.mdf" ! -name '._*' -print 2>/dev/null | sort
}

# Find the .ldf that pairs with a selected .mdf (same dir).
# Preference: <base>_log.ldf, <base>_Log.ldf, <base>.ldf, then sole .ldf, else none.
find_matching_ldf() {
  local mdf="$1"
  local dir base cand
  local ldfs=()

  dir="$(cd -- "$(dirname -- "$mdf")" && pwd)"
  base="$(basename "$mdf")"
  base="${base%.*}"

  for cand in "$dir/${base}_log.ldf" "$dir/${base}_Log.ldf" "$dir/${base}.ldf"; do
    if [[ -f "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done

  mapfile -t ldfs < <(find "$dir" -maxdepth 1 -type f -iname "*.ldf" ! -name '._*' -print 2>/dev/null)
  if ((${#ldfs[@]} == 1)); then
    printf '%s\n' "${ldfs[0]}"
  fi

  return 0
}

main() {
  forge_require_docker_access
  forge_require_cmd fzf
  forge_require_cmd find
  forge_require_cmd python3
  forge_assert_sensitive_config

  local container_name image host_port sql_user sqlcmd_path
  local container_root snapshots_container_path
  local data_bind_path snapshots_host_path sa_password source_paths_json container_user
  local selected_source selected_mdf selected_ldf mdf_basename base default_db_name db_name
  local data_dir target_mdf target_ldf conflict attach_files chown_owner

  container_name="$(forge_get docker.container_name)"
  image="$(forge_get docker.image)"
  host_port="$(forge_get docker.host_port)"
  sql_user="$(forge_get docker.sql_user)"
  container_root="$(forge_get docker.container_root)"
  snapshots_container_path="$(forge_get docker.container_snapshots_path)"
  sqlcmd_path="$(forge_get docker.sqlcmd_path)"
  data_bind_path="$(forge_get_path_from_root paths.data_bind_path paths.sql_storage_root)"
  snapshots_host_path="$(forge_get_path_from_root paths.restore_stage_path paths.sql_storage_root)"
  container_user="$(sql_container_user "$data_bind_path")"
  sa_password="$(forge_get sql.sa_password)"
  source_paths_json="$(forge_get_json restore.backup_source_paths)"

  [[ "$sql_user" == "sa" ]] || die "This restore flow currently supports sql_user=sa only."

  selected_source="$(select_source_path "$source_paths_json")" || die "No source path selected."
  [[ -n "$selected_source" ]] || die "No source path selected."

  selected_mdf="$(
    find_mdf_files "$selected_source" | fzf --prompt='Select .mdf to attach > ' --height=50%
  )" || die "No data file selected."
  [[ -n "$selected_mdf" && -f "$selected_mdf" ]] || die "No data file selected."

  selected_ldf="$(find_matching_ldf "$selected_mdf")"

  mdf_basename="$(basename "$selected_mdf")"
  base="${mdf_basename%.*}"
  base="${base%%.*}"
  base="${base%_Data}"
  base="${base%_data}"
  default_db_name="${base%%_*}"
  [[ -n "$default_db_name" ]] || default_db_name="$base"

  section "Attach Plan"
  log_info "Source      $selected_source"
  log_info "Data file   $mdf_basename"
  if [[ -n "$selected_ldf" ]]; then
    log_info "Log file    $(basename "$selected_ldf")"
  else
    log_warn "Log file    none found (log will be rebuilt)"
  fi
  read -r -p "Database name to attach into [$default_db_name]: " db_name
  db_name="${db_name:-$default_db_name}"
  [[ -n "$db_name" ]] || die "Database name cannot be empty."
  log_info "Database    $db_name"

  ensure_sql_container \
    "$container_name" \
    "$image" \
    "$host_port" \
    "$container_root" \
    "$snapshots_host_path" \
    "$snapshots_container_path" \
    "$data_bind_path" \
    "$sa_password" \
    "$container_user"

  wait_for_sql_ready "$container_name" "$sqlcmd_path" "$sa_password"

  data_dir="$container_root/data"
  target_mdf="$data_dir/${db_name}.mdf"
  target_ldf="$data_dir/${db_name}_log.ldf"

  # Refuse if another database already owns the target files.
  conflict="$(
    docker exec -i "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
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

  # Drop an existing DB with the same name (frees its physical files).
  log_step "Preparing target database [$db_name]..."
  docker exec -i "$container_name" \
    "$sqlcmd_path" \
    -S localhost -U sa -P "$sa_password" -C -d master \
    -b <<SQL_EOF
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
BEGIN
  ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [$db_name];
END;
SQL_EOF

  # Copy files into the container data dir under the target name.
  log_step "Staging data file -> $target_mdf"
  docker cp "$selected_mdf" "$container_name:$target_mdf" >/dev/null \
    || die "Failed to copy .mdf into container."

  if [[ -n "$selected_ldf" ]]; then
    log_step "Staging log file  -> $target_ldf"
    docker cp "$selected_ldf" "$container_name:$target_ldf" >/dev/null \
      || die "Failed to copy .ldf into container."
  fi

  if [[ "$container_user" == "mssql" ]]; then
    chown_owner="10001:0"
  else
    chown_owner="$container_user"
  fi

  docker exec -u 0 "$container_name" /bin/bash -lc "
    chown $chown_owner '$target_mdf' 2>/dev/null || true
    chmod 660 '$target_mdf' 2>/dev/null || true
    if [[ -f '$target_ldf' ]]; then
      chown $chown_owner '$target_ldf' 2>/dev/null || true
      chmod 660 '$target_ldf' 2>/dev/null || true
    fi
  " >/dev/null || true

  if [[ -n "$selected_ldf" ]]; then
    attach_files="( FILENAME = N'$target_mdf' ),
  ( FILENAME = N'$target_ldf' )
  FOR ATTACH;"
  else
    attach_files="( FILENAME = N'$target_mdf' )
  FOR ATTACH_REBUILD_LOG;"
  fi

  log_step "Attaching [$db_name] from: $target_mdf"

  docker exec -i "$container_name" \
    "$sqlcmd_path" \
    -S localhost -U sa -P "$sa_password" -C -d master \
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
    @st int = ERROR_STATE(),
    @ln int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('ATTACH FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH
SQL_EOF

  printf '\n'
  log_success "Database [$db_name] attached."

  section "SQL Ready"
  log_success "Server      localhost"
  log_success "Port        $host_port"
  log_success "Database    $db_name"
  log_success "User        $sql_user"
  log_success "Container   $container_name"
  log_success "SQLCMD      sqlcmd -S localhost,$host_port -U $sql_user -P '***' -C -d $db_name"
  log_info "Data file   $target_mdf"
  [[ -n "$selected_ldf" ]] && log_info "Log file    $target_ldf"
}

main "$@"
