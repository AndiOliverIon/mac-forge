#!/usr/bin/env bash
set -euo pipefail

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
  [[ -w "$snapshots_host_path" ]] || die "Snapshots path not writable: $snapshots_host_path"
  [[ -w "$data_bind_path" ]] || die "Data bind path not writable: $data_bind_path"

  prepare_sql_bind_path "$image" "$data_bind_path" "$container_root" "$container_user"

  if docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    existing_user="$(docker inspect --format '{{.Config.User}}' "$container_name" 2>/dev/null || true)"
    existing_data_mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "'"$container_root"'"}}{{.Source}}{{end}}{{end}}' "$container_name" 2>/dev/null || true)"
    existing_snapshots_mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "'"$snapshots_container_path"'"}}{{.Source}}{{end}}{{end}}' "$container_name" 2>/dev/null || true)"

    if [[ "$existing_user" != "$container_user" || "$existing_data_mount" != "$data_bind_path" || "$existing_snapshots_mount" != "$snapshots_host_path" ]]; then
      if docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
        die "Container '$container_name' is running with a different user or mount configuration. Stop and remove it so dbr can recreate it."
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

  python3 - "$source_paths_json" <<'PY' | fzf --prompt='Backup source path > ' --height=40%
import json
import sys

for item in json.loads(sys.argv[1]):
    if isinstance(item, str) and item.strip():
        print(item)
PY
}

find_backup_files() {
  local search_root="$1"
  [[ -d "$search_root" ]] || forge_die "Backup source path does not exist: $search_root"

  find "$search_root" -type f \( -iname "*.bak" -o -iname "*.bkp" \) -print 2>/dev/null | sort
}

main() {
  forge_require_cmd docker
  forge_require_cmd fzf
  forge_require_cmd find
  forge_require_cmd python3
  forge_assert_sensitive_config

  local container_name image host_port sql_user sqlcmd_path
  local container_root snapshots_container_path
  local data_bind_path snapshots_host_path sa_password source_paths_json container_user
  local selected_source selected_file backup_basename base default_db_name db_name
  local snapshot_filename snapshot_host_path snapshot_container_path
  local filelist_csv move_clauses

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

  selected_file="$(
    find_backup_files "$selected_source" | fzf --prompt='Select .bak to restore > ' --height=50%
  )" || die "No backup file selected."

  backup_basename="$(basename "$selected_file")"
  base="${backup_basename%.*}"
  base="${base%%.*}"
  default_db_name="${base%%_*}"
  [[ -n "$default_db_name" ]] || default_db_name="$base"

  section "Restore Plan"
  log_info "Source      $selected_source"
  log_info "Backup      $backup_basename"
  read -r -p "Database name to restore into [$default_db_name]: " db_name
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

  docker exec -u 0 "$container_name" /bin/bash -lc "
    mkdir -p '$snapshots_container_path' &&
    chown -R mssql:mssql '$snapshots_container_path' 2>/dev/null || true &&
    chmod 775 '$snapshots_container_path' 2>/dev/null || true
  " >/dev/null || die "Failed to prepare snapshots folder in container: $snapshots_container_path"

  snapshot_filename="$db_name.bak"
  snapshot_host_path="$snapshots_host_path/$snapshot_filename"
  snapshot_container_path="$snapshots_container_path/$snapshot_filename"

  if [[ "$selected_file" != "$snapshot_host_path" ]]; then
    log_step "Staging -> $snapshot_host_path"
    cp -f "$selected_file" "$snapshot_host_path"
  fi

  docker exec -u 0 "$container_name" /bin/bash -lc "
    chown mssql:mssql '$snapshot_container_path' 2>/dev/null || true
    chmod 660 '$snapshot_container_path' 2>/dev/null || true
  " >/dev/null || true

  [[ -f "$snapshot_host_path" ]] || die "Staged backup not found on host: $snapshot_host_path"

  filelist_csv="$(
    docker exec -i "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
      -r 1 -W -h -1 -s '|' -w 65535 <<SQL_EOF
SET NOCOUNT ON;
RESTORE FILELISTONLY
FROM DISK = N'$snapshot_container_path';
SQL_EOF
  )" || die "Failed to read FILELISTONLY from backup."

  [[ -n "${filelist_csv//$'\n'/}" ]] || die "FILELISTONLY returned no output."

  move_clauses="$(
    echo "$filelist_csv" | awk -F'|' -v db="$db_name" -v dir="$container_root/data" '
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

  log_step "Restoring [$db_name] from: $snapshot_container_path"

  docker exec -i "$container_name" \
    "$sqlcmd_path" \
    -S localhost -U sa -P "$sa_password" -C -d master \
    -b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
  IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
  BEGIN
    DECLARE @state nvarchar(60) = (SELECT state_desc FROM sys.databases WHERE name = N'$db_name');

    IF @state = N'RESTORING'
    BEGIN
      BEGIN TRY
        RESTORE DATABASE [$db_name] WITH RECOVERY;
      END TRY
      BEGIN CATCH
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
    @st int = ERROR_STATE(),
    @ln int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('RESTORE FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH
SQL_EOF

  printf '\n'
  log_success "Database [$db_name] restored."

  section "SQL Ready"
  log_success "Server      localhost"
  log_success "Port        $host_port"
  log_success "Database    $db_name"
  log_success "User        $sql_user"
  log_success "Container   $container_name"
  log_success "SQLCMD      sqlcmd -S localhost,$host_port -U $sql_user -P '***' -C -d $db_name"
  log_info "Staged bak  $snapshot_host_path"
}

main "$@"
