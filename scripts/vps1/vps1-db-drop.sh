#!/opt/homebrew/bin/bash
# vps1-db-drop.sh — drop a user database on vps1 (the actual live database in
# the tnisoft-mssql container, not a .bak file).
#
# Safety: requires typing the exact database name to confirm. System databases
# are never listed.
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
# Pick database
#######################################
vps1_log_step "Retrieving vps1 database list..."
mapfile -t DB_LIST < <(
  vps1_sqlcmd -h -1 -W -Q \
    "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb');" \
    | sed '/^$/d'
)
((${#DB_LIST[@]} > 0)) || vps1_die "No user databases found on vps1."

DB_SELECTED="$(printf '%s\n' "${DB_LIST[@]}" | fzf --prompt='Select vps1 database to DROP > ')" \
  || vps1_die "No database selected."

#######################################
# Strict confirmation
#######################################
echo
echo "⚠ You are about to PERMANENTLY DROP this database on vps1:"
echo "    $DB_SELECTED"
echo "  Container: $VPS1_SQL_CONTAINER   Server: $VPS1_SQL_SERVER"
echo
echo "Type the exact database name to confirm."
read -r -p "> " answer
[[ "$answer" == "$DB_SELECTED" ]] || vps1_die "Confirmation mismatch. Aborted (nothing was dropped)."

#######################################
# Drop
#######################################
vps1_log_step "Dropping database [$DB_SELECTED] on vps1..."
vps1_sqlcmd -b <<SQL_EOF
SET NOCOUNT ON;
BEGIN TRY
  IF DB_ID(N'$DB_SELECTED') IS NULL
  BEGIN
    RAISERROR('Database [%s] does not exist.', 16, 1, N'$DB_SELECTED');
  END

  ALTER DATABASE [$DB_SELECTED] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [$DB_SELECTED];
END TRY
BEGIN CATCH
  DECLARE
    @num int = ERROR_NUMBER(),
    @msg nvarchar(4000) = ERROR_MESSAGE();
  PRINT CONCAT('DROP FAILED (', @num, '): ', @msg);
  THROW;
END CATCH
SQL_EOF

echo "✔ Database [$DB_SELECTED] dropped on vps1."
