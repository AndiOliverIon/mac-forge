#!/usr/bin/env bash
# vps1-db-attr.sh — change an attribute of a selected vps1 database.
#
# Flow: pick a database (fzf) -> pick an action (fzf) -> apply.
#
# Actions implemented so far:
#   collation — for client backups restored onto vps1 (v1r). Restore keeps
#               the source collation; this changes the database default so
#               the copy can match the instance (or another chosen
#               collation). Existing char/varchar columns are not rewritten.
#               Catalog objects that block ALTER DATABASE COLLATE (check
#               constraints, computed columns, filtered indexes, schema-bound
#               modules, …) are inventoried up front, dropped, then
#               recreated. PRIMARY KEY / UNIQUE constraint indexes and
#               encrypted modules are not auto-dropped. Exclusive access is
#               required; MULTI_USER is always restored.
#
# Alias: v1attr (= vps1-attr).
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
# T-SQL helpers (escaping)
#######################################
tsql_ident() { local n="$1"; n="${n//]/]]}"; printf '[%s]' "$n"; }
tsql_str() { local s="$1"; s="${s//\'/\'\'}"; printf '%s' "$s"; }

sql_scalar() {
  vps1_sqlcmd -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r' | sed '/^$/d' | head -n 1
}

#######################################
# Catalog collation change (runs inside the selected database).
# Mode=list  -> print KIND<TAB>object rows
# Mode=apply -> drop blockers, COLLATE, recreate
#######################################
run_collation_sql() {
  local mode="$1" coll="${2:-none}"
  vps1_sqlcmd -d "$selected_db" -h -1 -W -y 0 -Y 0 -b \
    -v Mode="$mode" -v TargetCollation="$coll" <<'SQL_EOF'
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;

DECLARE @mode varchar(10) = '$(Mode)';
DECLARE @target sysname = N'$(TargetCollation)';

IF OBJECT_ID('tempdb..#work') IS NOT NULL DROP TABLE #work;
CREATE TABLE #work (
  id int IDENTITY(1,1) PRIMARY KEY,
  drop_order int NOT NULL,
  kind varchar(32) COLLATE DATABASE_DEFAULT NOT NULL,
  obj nvarchar(256) COLLATE DATABASE_DEFAULT NOT NULL,
  drop_sql nvarchar(max) COLLATE DATABASE_DEFAULT NULL,
  create_sql nvarchar(max) COLLATE DATABASE_DEFAULT NULL,
  auto bit NOT NULL,
  dropped bit NOT NULL DEFAULT 0,
  recreated bit NOT NULL DEFAULT 0
);

-- Filtered indexes, indexes on collation-dependent computed columns, indexes on views.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 10, 'INDEX',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N'.' + QUOTENAME(i.name),
       N'DROP INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';',
       N'CREATE ' + CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END
         + CASE i.type WHEN 1 THEN N'CLUSTERED ' ELSE N'NONCLUSTERED ' END
         + N'INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
         + N' (' + keys.list + N')'
         + ISNULL(N' INCLUDE (' + incs.list + N')', N'')
         + CASE WHEN i.has_filter = 1 THEN N' WHERE ' + i.filter_definition ELSE N'' END + N';',
       1
FROM sys.indexes i
JOIN sys.objects o ON o.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
CROSS APPLY (
  SELECT STRING_AGG(CAST(QUOTENAME(c.name) + CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N'' END AS nvarchar(max)), N', ')
           WITHIN GROUP (ORDER BY ic.key_ordinal)
  FROM sys.index_columns ic
  JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
  WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
) keys(list)
OUTER APPLY (
  SELECT STRING_AGG(CAST(QUOTENAME(c.name) AS nvarchar(max)), N', ')
           WITHIN GROUP (ORDER BY ic.index_column_id)
  FROM sys.index_columns ic
  JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
  WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
) incs(list)
WHERE i.is_hypothetical = 0
  AND i.name IS NOT NULL
  AND i.type IN (1, 2)
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND keys.list IS NOT NULL
  AND (
    i.has_filter = 1
    OR o.type = 'V'
    OR EXISTS (
      SELECT 1
      FROM sys.index_columns ic
      JOIN sys.computed_columns cc ON cc.object_id = ic.object_id AND cc.column_id = ic.column_id
      WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
        AND cc.uses_database_collation = 1
    )
  );

-- PK/UNIQUE sitting on a collation-dependent computed column: visible, not dropped.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 15, 'MANUAL',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N'.' + QUOTENAME(i.name),
       NULL, NULL, 0
FROM sys.indexes i
JOIN sys.objects o ON o.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE i.name IS NOT NULL
  AND (i.is_primary_key = 1 OR i.is_unique_constraint = 1)
  AND EXISTS (
    SELECT 1
    FROM sys.index_columns ic
    JOIN sys.computed_columns cc ON cc.object_id = ic.object_id AND cc.column_id = ic.column_id
    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
      AND cc.uses_database_collation = 1
  );

-- Blocking statistics (not the ones that belong to an index we already listed).
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 20, 'STATS',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N'.' + QUOTENAME(st.name),
       N'DROP STATISTICS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N'.' + QUOTENAME(st.name) + N';',
       CASE WHEN st.user_created = 1 THEN
         N'CREATE STATISTICS ' + QUOTENAME(st.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
           + N' (' + cols.list + N')'
           + CASE WHEN st.has_filter = 1 THEN N' WHERE ' + st.filter_definition ELSE N'' END + N';'
       END,
       1
FROM sys.stats st
JOIN sys.objects o ON o.object_id = st.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
CROSS APPLY (
  SELECT STRING_AGG(CAST(QUOTENAME(c.name) AS nvarchar(max)), N', ')
           WITHIN GROUP (ORDER BY sc.stats_column_id)
  FROM sys.stats_columns sc
  JOIN sys.columns c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
  WHERE sc.object_id = st.object_id AND sc.stats_id = st.stats_id
) cols(list)
WHERE cols.list IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM sys.indexes ix
    WHERE ix.object_id = st.object_id AND ix.name = st.name
  )
  AND (
    st.has_filter = 1
    OR EXISTS (
      SELECT 1
      FROM sys.stats_columns sc
      JOIN sys.computed_columns cc ON cc.object_id = sc.object_id AND cc.column_id = sc.column_id
      WHERE sc.object_id = st.object_id AND sc.stats_id = st.stats_id
        AND cc.uses_database_collation = 1
    )
  );

-- CHECK constraints always block catalog collation change.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 30, 'CHECK',
       QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N'.' + QUOTENAME(ck.name),
       N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
         + N' DROP CONSTRAINT ' + QUOTENAME(ck.name) + N';',
       N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
         + N' ADD CONSTRAINT ' + QUOTENAME(ck.name) + N' CHECK ' + ck.definition + N';',
       1
FROM sys.check_constraints ck
JOIN sys.tables t ON t.object_id = ck.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id;

-- Permissions on modules we will drop (recreate after the module).
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 40, 'PERM',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name),
       NULL,
       CASE dp.state
         WHEN 'G' THEN N'GRANT '
         WHEN 'W' THEN N'GRANT '
         WHEN 'D' THEN N'DENY '
         WHEN 'R' THEN N'REVOKE '
         ELSE N'GRANT '
       END + dp.permission_name + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
         + N' TO ' + QUOTENAME(USER_NAME(dp.grantee_principal_id))
         + CASE WHEN dp.state = 'W' THEN N' WITH GRANT OPTION' ELSE N'' END + N';',
       1
FROM sys.sql_modules sm
JOIN sys.objects o ON o.object_id = sm.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.database_permissions dp ON dp.class = 1 AND dp.major_id = o.object_id
WHERE sm.uses_database_collation = 1
  AND dp.permission_name IS NOT NULL;

-- Encrypted modules that block COLLATE: cannot be scripted.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 48, 'ENCRYPTED',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name),
       NULL, NULL, 0
FROM sys.sql_modules sm
JOIN sys.objects o ON o.object_id = sm.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE sm.uses_database_collation = 1
  AND sm.definition IS NULL;

-- Schema-bound / collation-dependent modules.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT CASE WHEN o.type = 'TR' THEN 45 ELSE 50 END,
       'MODULE',
       QUOTENAME(s.name) + N'.' + QUOTENAME(o.name),
       N'DROP ' + CASE o.type
                    WHEN 'V' THEN N'VIEW'
                    WHEN 'P' THEN N'PROCEDURE'
                    WHEN 'TR' THEN N'TRIGGER'
                    ELSE N'FUNCTION'
                  END
         + N' ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';',
       CASE
         WHEN LTRIM(sm.definition) LIKE 'CREATE OR ALTER %'
           THEN N'CREATE ' + SUBSTRING(LTRIM(sm.definition), 17, LEN(LTRIM(sm.definition)))
         WHEN LTRIM(sm.definition) LIKE 'ALTER %'
           THEN N'CREATE ' + SUBSTRING(LTRIM(sm.definition), 7, LEN(LTRIM(sm.definition)))
         ELSE sm.definition
       END,
       1
FROM sys.sql_modules sm
JOIN sys.objects o ON o.object_id = sm.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE sm.uses_database_collation = 1
  AND sm.definition IS NOT NULL
  AND o.type IN ('V', 'P', 'FN', 'IF', 'TF', 'TR');

-- Triggers on modules we drop, if the trigger itself is not already listed.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 45, 'TRIGGER',
       QUOTENAME(s.name) + N'.' + QUOTENAME(tr.name),
       NULL,
       CASE
         WHEN LTRIM(sm.definition) LIKE 'CREATE OR ALTER %'
           THEN N'CREATE ' + SUBSTRING(LTRIM(sm.definition), 17, LEN(LTRIM(sm.definition)))
         WHEN LTRIM(sm.definition) LIKE 'ALTER %'
           THEN N'CREATE ' + SUBSTRING(LTRIM(sm.definition), 7, LEN(LTRIM(sm.definition)))
         ELSE sm.definition
       END,
       1
FROM sys.triggers tr
JOIN sys.sql_modules sm ON sm.object_id = tr.object_id
JOIN sys.objects o ON o.object_id = tr.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE sm.definition IS NOT NULL
  AND tr.parent_id IN (
    SELECT o2.object_id
    FROM sys.sql_modules sm2
    JOIN sys.objects o2 ON o2.object_id = sm2.object_id
    WHERE sm2.uses_database_collation = 1
  )
  AND NOT EXISTS (
    SELECT 1 FROM #work w
    WHERE w.kind IN ('MODULE', 'TRIGGER', 'ENCRYPTED')
      AND w.obj = QUOTENAME(s.name) + N'.' + QUOTENAME(tr.name)
  );

-- Computed columns that use the database collation.
INSERT #work (drop_order, kind, obj, drop_sql, create_sql, auto)
SELECT 60, 'COLUMN',
       QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N'.' + QUOTENAME(cc.name),
       N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
         + N' DROP COLUMN ' + QUOTENAME(cc.name) + N';',
       N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
         + N' ADD ' + QUOTENAME(cc.name) + N' AS ' + cc.definition
         + CASE WHEN cc.is_persisted = 1 THEN N' PERSISTED' ELSE N'' END
         + CASE WHEN cc.is_persisted = 1 AND cc.is_nullable = 0 THEN N' NOT NULL' ELSE N'' END
         + N';',
       1
FROM sys.computed_columns cc
JOIN sys.tables t ON t.object_id = cc.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE cc.uses_database_collation = 1;

IF @mode = 'list'
BEGIN
  SELECT kind + CHAR(9) + obj + CASE WHEN auto = 0 THEN CHAR(9) + N'(not auto-handled)' ELSE N'' END
  FROM #work
  WHERE kind <> 'PERM'
  ORDER BY drop_order, obj;
  RETURN;
END;

IF EXISTS (SELECT 1 FROM #work WHERE kind = 'ENCRYPTED')
BEGIN
  RAISERROR('Encrypted module(s) depend on the database collation and cannot be scripted.', 16, 1);
  RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM sys.fn_helpcollations() WHERE name COLLATE DATABASE_DEFAULT = @target)
BEGIN
  RAISERROR('Unknown collation: %s', 16, 1, @target);
  RETURN;
END;

DECLARE @id int, @sql nvarchar(max), @kind varchar(32), @obj nvarchar(256);
DECLARE @pass int, @moved int, @recreate_failures int = 0, @collate_ok bit = 0;

SET @pass = 0;
SET @moved = 1;
WHILE @moved > 0 AND @pass < 20
BEGIN
  SET @pass += 1;
  SET @moved = 0;

  DECLARE dcur CURSOR LOCAL FAST_FORWARD FOR
    SELECT id, drop_sql, kind, obj
    FROM #work
    WHERE auto = 1 AND drop_sql IS NOT NULL AND dropped = 0
    ORDER BY drop_order, id;

  OPEN dcur;
  FETCH NEXT FROM dcur INTO @id, @sql, @kind, @obj;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      PRINT N'Dropping ' + @kind + N' ' + @obj;
      EXEC(@sql);
      UPDATE #work SET dropped = 1 WHERE id = @id;
      SET @moved += 1;
    END TRY
    BEGIN CATCH
      PRINT N'  (defer) ' + @obj + N': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM dcur INTO @id, @sql, @kind, @obj;
  END
  CLOSE dcur;
  DEALLOCATE dcur;
END;

IF EXISTS (SELECT 1 FROM #work WHERE auto = 1 AND drop_sql IS NOT NULL AND dropped = 0)
  PRINT N'Some blockers could not be dropped; COLLATE will likely fail.';

BEGIN TRY
  SET @sql = N'ALTER DATABASE CURRENT COLLATE ' + @target + N';';
  PRINT N'Changing catalog collation to ' + @target;
  EXEC(@sql);
  SET @collate_ok = 1;
END TRY
BEGIN CATCH
  PRINT ERROR_MESSAGE();
END CATCH

SET @pass = 0;
SET @moved = 1;
WHILE @moved > 0 AND @pass < 20
BEGIN
  SET @pass += 1;
  SET @moved = 0;

  DECLARE ccur CURSOR LOCAL FAST_FORWARD FOR
    SELECT id, create_sql, kind, obj
    FROM #work
    WHERE auto = 1
      AND create_sql IS NOT NULL
      AND recreated = 0
      AND (drop_sql IS NULL OR dropped = 1)
    ORDER BY drop_order DESC, id DESC;

  OPEN ccur;
  FETCH NEXT FROM ccur INTO @id, @sql, @kind, @obj;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      PRINT N'Recreating ' + @kind + N' ' + @obj;
      EXEC(@sql);
      UPDATE #work SET recreated = 1 WHERE id = @id;
      SET @moved += 1;
    END TRY
    BEGIN CATCH
      PRINT N'  (defer) ' + @obj + N': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM ccur INTO @id, @sql, @kind, @obj;
  END
  CLOSE ccur;
  DEALLOCATE ccur;
END

SELECT @recreate_failures = COUNT(*)
FROM #work
WHERE auto = 1 AND create_sql IS NOT NULL AND recreated = 0
  AND (drop_sql IS NULL OR dropped = 1);

IF @collate_ok = 0
BEGIN
  RAISERROR('ALTER DATABASE COLLATE failed. Dropped objects were recreated when possible. Collation unchanged.', 16, 1);
  RETURN;
END

IF @recreate_failures > 0
BEGIN
  RAISERROR('Catalog collation changed, but one or more objects failed to recreate. See messages above.', 16, 1);
  RETURN;
END

PRINT N'Catalog collation is now ' + @target;
SQL_EOF
}

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
  printf '%s\n' "${DBS[@]}" | fzf --prompt='Select vps1 database > ' --height=60% --reverse
)" || vps1_die "No database selected."
[[ -n "$selected_db" ]] || vps1_die "No database selected."

db_ident="$(tsql_ident "$selected_db")"
db_literal="$(tsql_str "$selected_db")"

#######################################
# Pick an action
#######################################
ACTIONS=("collation")

selected_action="$(
  printf '%s\n' "${ACTIONS[@]}" | fzf --prompt='Select action > ' --height=40% --reverse
)" || vps1_die "No action selected."
[[ -n "$selected_action" ]] || vps1_die "No action selected."

#######################################
# Action: collation
#######################################
change_collation() {
  local current instance target picked confirm new_collation apply_status blockers
  local -a COMMON_COLLATIONS choices display
  local c suffix

  current="$(sql_scalar "SELECT CONVERT(nvarchar(128), DATABASEPROPERTYEX(N'$db_literal', 'Collation'));")" \
    || vps1_die "Failed to read current collation of [$selected_db]."
  [[ -n "$current" ]] || vps1_die "Could not determine current collation of [$selected_db]."

  instance="$(sql_scalar "SELECT CONVERT(nvarchar(128), SERVERPROPERTY('Collation'));")" \
    || vps1_die "Failed to read instance collation."
  [[ -n "$instance" ]] || vps1_die "Could not determine instance collation."

  COMMON_COLLATIONS=(
    "SQL_Latin1_General_CP1_CI_AS"
    "SQL_Latin1_General_CP1_CS_AS"
    "Latin1_General_CI_AS"
    "Latin1_General_CS_AS"
    "French_CI_AS"
    "French_CS_AS"
    "Romanian_CI_AS"
    "Modern_Spanish_CI_AS"
    "German_PhoneBook_CI_AS"
    "Cyrillic_General_CI_AS"
    "Turkish_CI_AS"
    "Polish_CI_AS"
    "Hungarian_CI_AS"
    "Arabic_CI_AS"
    "Hebrew_CI_AS"
    "Chinese_PRC_CI_AS"
    "Japanese_CI_AS"
  )

  choices=("$instance")
  for c in "${COMMON_COLLATIONS[@]}"; do
    [[ "$c" == "$instance" ]] && continue
    choices+=("$c")
  done
  choices+=("Custom...")

  display=()
  for c in "${choices[@]}"; do
    suffix=""
    [[ "$c" == "$instance" ]] && suffix="  (instance)"
    [[ "$c" == "$current" && "$c" != "$instance" ]] && suffix="  (current)"
    [[ "$c" == "$current" && "$c" == "$instance" ]] && suffix="  (instance, current)"
    display+=("${c}${suffix}")
  done

  echo
  echo "Database            : $selected_db  (vps1: $VPS1_SQL_SERVER)"
  echo "Current collation   : $current"
  echo "Instance collation  : $instance"
  echo

  picked="$(
    printf '%s\n' "${display[@]}" \
      | fzf --prompt="Change [$selected_db] catalog collation to > " --height=60% --reverse
  )" || vps1_die "No collation selected."
  [[ -n "$picked" ]] || vps1_die "No collation selected."

  target="${picked%%  (*}"
  if [[ "$target" == "Custom..." ]]; then
    read -r -p "Enter collation name: " target
    [[ -n "$target" ]] || vps1_die "Collation name cannot be empty."
  fi
  [[ "$target" =~ ^[A-Za-z0-9_]+$ ]] || vps1_die "Refusing collation name with unexpected characters: $target"
  [[ "$target" != "$current" ]] || vps1_die "Selected collation matches the current one; nothing to do."

  vps1_log_step "Scanning [$selected_db] for objects that block a catalog collation change..."
  blockers="$(run_collation_sql list "$target" | tr -d '\r' | sed '/^$/d')" || \
    vps1_die "Failed to inventory collation blockers in [$selected_db]."

  if grep -q '^ENCRYPTED' <<< "$blockers"; then
    echo "$blockers"
    vps1_die "Encrypted module(s) depend on the database collation and cannot be scripted. Aborting."
  fi

  echo
  if [[ -z "$blockers" ]]; then
    echo "No catalog blockers found."
  else
    echo "Will drop and recreate:"
    sed 's/^/  /' <<< "$blockers"
  fi
  echo
  echo "⚠ [$selected_db] will be set SINGLE_USER (dropping other connections)."
  echo "  This changes the database default collation only; existing columns stay as they are."
  if grep -q '(not auto-handled)' <<< "$blockers"; then
    echo "  Some objects will not be auto-dropped (PRIMARY KEY/UNIQUE on a computed column)."
    echo "  COLLATE may still fail for those; dropped objects are recreated either way."
  fi
  read -r -p "Change [$selected_db] catalog collation: $current -> $target ? [y/N] " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" ]] || vps1_die "Aborted (no changes made)."

  vps1_log_step "Setting [$selected_db] to SINGLE_USER (exclusive access)..."
  vps1_sqlcmd -b -Q "ALTER DATABASE $db_ident SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" \
    || vps1_die "Failed to switch [$selected_db] to SINGLE_USER; no changes made."

  apply_status=0
  run_collation_sql apply "$target" || apply_status=$?

  vps1_log_step "Restoring [$selected_db] to MULTI_USER..."
  if vps1_sqlcmd -b -Q "ALTER DATABASE $db_ident SET MULTI_USER;"; then
    vps1_log_step "[$selected_db] is back to MULTI_USER."
  else
    echo "⚠ Failed to confirm MULTI_USER restore for [$selected_db]; check sys.databases.user_access_desc." >&2
  fi

  new_collation="$(sql_scalar "SELECT CONVERT(nvarchar(128), DATABASEPROPERTYEX(N'$db_literal', 'Collation'));")" || new_collation=""

  if ((apply_status != 0)) || [[ "$new_collation" != "$target" ]]; then
    vps1_die "Collation change did not complete. [$selected_db] collation is now: ${new_collation:-unknown}."
  fi

  echo
  echo "✔ Catalog collation changed for [$selected_db]"
  echo "   before : $current"
  echo "   after  : $new_collation"
}

#######################################
# Dispatch
#######################################
case "$selected_action" in
  collation) change_collation ;;
  *) vps1_die "Unknown action: $selected_action" ;;
esac
