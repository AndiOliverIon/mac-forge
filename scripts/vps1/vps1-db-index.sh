#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
  [ -x /opt/homebrew/bin/bash ] && exec /opt/homebrew/bin/bash "$0" "$@"
  exec bash "$0" "$@"
fi
# vps1-db-index.sh — rebuild all indexes in a selected vps1 SQL database.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd sqlcmd
vps1_require_cmd fzf
vps1_load_connection
vps1_wait_for_sql_ready

#######################################
# Pick one ONLINE user database
#######################################
vps1_log_step "Retrieving ONLINE user databases on vps1..."
mapfile -t DBS < <(
  vps1_sqlcmd -h -1 -W -Q \
    "SET NOCOUNT ON; SELECT name FROM sys.databases
       WHERE database_id > 4
         AND state_desc = 'ONLINE'
       ORDER BY name;" \
    | tr -d '\r' | sed '/^$/d'
)
((${#DBS[@]} > 0)) || vps1_die "No ONLINE user databases found on vps1."

selected_db="$(
  printf '%s\n' "${DBS[@]}" | fzf --prompt='Rebuild indexes in vps1 database > ' --height=60% --reverse
)" || vps1_die "No database selected."
[[ -n "$selected_db" ]] || vps1_die "No database selected."

echo
echo "Server   : $VPS1_SQL_SERVER"
echo "Database : $selected_db"
echo "Action   : rebuild all indexes on indexed tables/views"
echo
read -r -p "Proceed with rebuilding all indexes in [$selected_db] on vps1? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || vps1_die "Aborted (no changes made)."

#######################################
# Rebuild indexes
#######################################
vps1_log_step "Rebuilding indexes in [$selected_db] on vps1..."

vps1_sqlcmd -b -d "$selected_db" <<'SQL_EOF'
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

echo "✔ Index rebuild completed for [$selected_db] on vps1."
