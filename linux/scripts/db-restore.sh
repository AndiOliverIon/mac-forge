#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/forge.sh"

log_step() {
  echo "-> $*"
}

wait_for_sql_ready() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"
  local max_tries=30
  local i

  log_step "Waiting for SQL Server in container '$container_name'..."

  for ((i = 1; i <= max_tries; i++)); do
    if docker exec "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
      -Q "SELECT 1" >/dev/null 2>&1; then
      log_step "SQL Server is ready (attempt $i)."
      return 0
    fi
    sleep 2
  done

  forge_die "SQL Server did not become ready."
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

  mkdir -p "$snapshots_host_path" "$data_bind_path"
  [[ -w "$snapshots_host_path" ]] || forge_die "Snapshots path not writable: $snapshots_host_path"
  [[ -w "$data_bind_path" ]] || forge_die "Data bind path not writable: $data_bind_path"

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
  local data_bind_path snapshots_host_path sa_password source_paths_json
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
  data_bind_path="$(forge_get_path paths.data_bind_path)"
  snapshots_host_path="$(forge_get_path paths.restore_stage_path)"
  sa_password="$(forge_get sql.sa_password)"
  source_paths_json="$(forge_get_json restore.backup_source_paths)"

  [[ "$sql_user" == "sa" ]] || forge_die "This restore flow currently supports sql_user=sa only."

  selected_source="$(select_source_path "$source_paths_json")" || forge_die "No source path selected."
  [[ -n "$selected_source" ]] || forge_die "No source path selected."

  selected_file="$(
    find_backup_files "$selected_source" | fzf --prompt='Select .bak to restore > ' --height=50%
  )" || forge_die "No backup file selected."

  backup_basename="$(basename "$selected_file")"
  base="${backup_basename%.*}"
  base="${base%%.*}"
  default_db_name="${base%%_*}"
  [[ -n "$default_db_name" ]] || default_db_name="$base"

  echo "Selected source : $selected_source"
  echo "Selected backup : $backup_basename"
  read -r -p "Database name to restore into [$default_db_name]: " db_name
  db_name="${db_name:-$default_db_name}"
  [[ -n "$db_name" ]] || forge_die "Database name cannot be empty."

  ensure_sql_container \
    "$container_name" \
    "$image" \
    "$host_port" \
    "$container_root" \
    "$snapshots_host_path" \
    "$snapshots_container_path" \
    "$data_bind_path" \
    "$sa_password"

  wait_for_sql_ready "$container_name" "$sqlcmd_path" "$sa_password"

  docker exec -u 0 "$container_name" /bin/bash -lc "
    mkdir -p '$snapshots_container_path' &&
    chown -R mssql:mssql '$snapshots_container_path' 2>/dev/null || true &&
    chmod 775 '$snapshots_container_path' 2>/dev/null || true
  " >/dev/null || forge_die "Failed to prepare snapshots folder in container: $snapshots_container_path"

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

  [[ -f "$snapshot_host_path" ]] || forge_die "Staged backup not found on host: $snapshot_host_path"

  filelist_csv="$(
    docker exec -i "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
      -r 1 -W -h -1 -s '|' -w 65535 <<SQL_EOF
SET NOCOUNT ON;
RESTORE FILELISTONLY
FROM DISK = N'$snapshot_container_path';
SQL_EOF
  )" || forge_die "Failed to read FILELISTONLY from backup."

  [[ -n "${filelist_csv//$'\n'/}" ]] || forge_die "FILELISTONLY returned no output."

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

  [[ -n "$move_clauses" ]] || forge_die "Could not generate MOVE clauses."

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

  echo "OK: Database [$db_name] restored."
  echo "Staged backup: $snapshot_host_path"
}

main "$@"
