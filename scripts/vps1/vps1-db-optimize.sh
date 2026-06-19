#!/opt/homebrew/bin/bash
# vps1-db-optimize.sh — shrink/optimize a vps1 database to reduce its disk
# footprint. Intended for inspection-only databases imported onto vps1, where the
# original size is irrelevant and the vps disk is the bottleneck.
#
# What it does (best-effort: each step is independent and failures are skipped,
# never aborting the rest):
#   1. Switch recovery model FULL -> SIMPLE   (allows the log to truncate)
#   2. CHECKPOINT                             (flush so the log can shrink)
#   3. Shrink every LOG file  -> ~1 MB
#   4. Shrink every DATA file -> TRUNCATEONLY, then sized toward used space
#
# It does NOT delete any rows/data. A future per-profile "certified" cleanup is
# a separate concern.
#
# WARNING: SET RECOVERY SIMPLE drops point-in-time (log-chain) restore for the
# database. That is intended here — these are throwaway inspection databases.
#
# Alias: v1opt (= vps1-optimize).
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
# [identifier] with ] doubled.
tsql_ident() { local n="$1"; n="${n//]/]]}"; printf '[%s]' "$n"; }
# 'string literal' body with ' doubled (caller adds the quotes).
tsql_str() { local s="$1"; s="${s//\'/\'\'}"; printf '%s' "$s"; }

#######################################
# Pick one ONLINE user database
#######################################
vps1_log_step "Retrieving ONLINE user databases on vps1..."
mapfile -t DBS < <(
  vps1_sqlcmd -h -1 -W -Q \
    "SET NOCOUNT ON; SELECT name FROM sys.databases
       WHERE name NOT IN ('master','tempdb','model','msdb')
         AND state_desc = 'ONLINE'
       ORDER BY name;" \
    | tr -d '\r' | sed '/^$/d'
)
((${#DBS[@]} > 0)) || vps1_die "No ONLINE user databases found on vps1."

selected_db="$(
  printf '%s\n' "${DBS[@]}" | fzf --prompt='Optimize database > ' --height=60% --reverse
)" || vps1_die "No database selected."
[[ -n "$selected_db" ]] || vps1_die "No database selected."

db_ident="$(tsql_ident "$selected_db")"
db_literal="$(tsql_str "$selected_db")"

#######################################
# Size reporting helper: prints "data|log|total" in MB
#######################################
get_sizes() {
  vps1_sqlcmd -h -1 -W -s '|' -Q \
    "SET NOCOUNT ON;
     SELECT
       CAST(ISNULL(SUM(CASE WHEN type = 0 THEN size END), 0) * 8.0 / 1024 AS DECIMAL(18,1)),
       CAST(ISNULL(SUM(CASE WHEN type = 1 THEN size END), 0) * 8.0 / 1024 AS DECIMAL(18,1)),
       CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18,1))
     FROM sys.master_files
     WHERE database_id = DB_ID('$db_literal');" \
    | tr -d '\r' | sed '/^$/d' | head -n 1
}

before="$(get_sizes)" || vps1_die "Failed to read current size of [$selected_db]."
before_data="${before%%|*}"
before_total="${before##*|}"
before_log="${before#*|}"; before_log="${before_log%%|*}"

#######################################
# Confirm
#######################################
echo
echo "Database : $selected_db  (vps1: $VPS1_SQL_SERVER)"
echo "Current  : data ${before_data} MB  |  log ${before_log} MB  |  total ${before_total} MB"
echo
echo "This will, best-effort:"
echo "  • set recovery model to SIMPLE  (drops point-in-time restore)"
echo "  • checkpoint and shrink the transaction log file(s)"
echo "  • shrink the data file(s) to reclaim unused space"
echo "No rows/data are deleted."
echo
read -r -p "Proceed with optimizing [$selected_db]? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || vps1_die "Aborted (no changes made)."

#######################################
# Run the optimization batch
#   Each step is wrapped in TRY/CATCH so a failure is reported and skipped
#   without aborting the remaining steps.
#######################################
echo
vps1_log_step "Optimizing [$selected_db]..."

optimize_sql="USE $db_ident;
SET NOCOUNT ON;

DECLARE @name sysname, @sql nvarchar(max), @usedmb int;

BEGIN TRY
  ALTER DATABASE $db_ident SET RECOVERY SIMPLE;
  PRINT '  [ok]   recovery model -> SIMPLE';
END TRY
BEGIN CATCH
  PRINT '  [skip] recovery SIMPLE failed: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
  CHECKPOINT;
  PRINT '  [ok]   checkpoint';
END TRY
BEGIN CATCH
  PRINT '  [skip] checkpoint failed: ' + ERROR_MESSAGE();
END CATCH;

DECLARE log_cur CURSOR LOCAL FAST_FORWARD FOR
  SELECT name FROM sys.database_files WHERE type_desc = 'LOG';
OPEN log_cur;
FETCH NEXT FROM log_cur INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    SET @sql = N'DBCC SHRINKFILE (' + QUOTENAME(@name, '''') + N', 1);';
    EXEC (@sql);
    PRINT '  [ok]   shrank log file ' + @name;
  END TRY
  BEGIN CATCH
    PRINT '  [skip] log shrink ' + @name + ': ' + ERROR_MESSAGE();
  END CATCH;
  FETCH NEXT FROM log_cur INTO @name;
END
CLOSE log_cur;
DEALLOCATE log_cur;

DECLARE data_cur CURSOR LOCAL FAST_FORWARD FOR
  SELECT name FROM sys.database_files WHERE type_desc = 'ROWS';
OPEN data_cur;
FETCH NEXT FROM data_cur INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    SET @sql = N'DBCC SHRINKFILE (' + QUOTENAME(@name, '''') + N', TRUNCATEONLY);';
    EXEC (@sql);
    PRINT '  [ok]   truncate-only data file ' + @name;
  END TRY
  BEGIN CATCH
    PRINT '  [skip] data truncate ' + @name + ': ' + ERROR_MESSAGE();
  END CATCH;

  BEGIN TRY
    SET @usedmb = CAST(FILEPROPERTY(@name, 'SpaceUsed') * 8.0 / 1024 AS int);
    IF @usedmb IS NULL OR @usedmb < 1 SET @usedmb = 1;
    SET @sql = N'DBCC SHRINKFILE (' + QUOTENAME(@name, '''') + N', ' + CAST(@usedmb AS nvarchar(20)) + N');';
    EXEC (@sql);
    PRINT '  [ok]   shrank data file ' + @name + ' toward ~' + CAST(@usedmb AS nvarchar(20)) + ' MB';
  END TRY
  BEGIN CATCH
    PRINT '  [skip] data shrink ' + @name + ': ' + ERROR_MESSAGE();
  END CATCH;

  FETCH NEXT FROM data_cur INTO @name;
END
CLOSE data_cur;
DEALLOCATE data_cur;"

# Best-effort: don't let a non-zero from inside the batch abort the script.
vps1_sqlcmd -Q "$optimize_sql" || echo "  (sqlcmd reported a non-zero exit; individual step results are above)"

#######################################
# Final report
#######################################
after="$(get_sizes)" || vps1_die "Optimization ran but failed to re-read size of [$selected_db]."
after_data="${after%%|*}"
after_total="${after##*|}"
after_log="${after#*|}"; after_log="${after_log%%|*}"

reclaimed="$(awk -v b="$before_total" -v a="$after_total" 'BEGIN { printf "%.1f", b - a }')"

echo
echo "✔ Optimization complete for [$selected_db]"
echo "   before : data ${before_data} MB  |  log ${before_log} MB  |  total ${before_total} MB"
echo "   after  : data ${after_data} MB  |  log ${after_log} MB  |  total ${after_total} MB"
echo "   freed  : ${reclaimed} MB"
