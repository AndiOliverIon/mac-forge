#!/opt/homebrew/bin/bash
# vps1-db-drop.sh — drop user database(s) on vps1 (the actual live databases in
# the tnisoft-mssql container, not .bak files).
#
# Safety: multi-select the databases to drop, then type 'delete' to confirm.
# System databases are never listed.
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

mapfile -t SELECTED < <(
  printf '%s\n' "${DB_LIST[@]}" \
    | fzf --multi --prompt='Select vps1 database(s) to DROP > ' \
          --header='TAB to mark multiple, ENTER to confirm selection' \
          --height=60% --reverse
)
((${#SELECTED[@]} > 0)) || vps1_die "No database selected."

#######################################
# Strict confirmation
#######################################
echo
echo "⚠ You are about to PERMANENTLY DROP these database(s) on vps1:"
for name in "${SELECTED[@]}"; do
  echo "    $name"
done
echo "  Container: $VPS1_SQL_CONTAINER   Server: $VPS1_SQL_SERVER"
echo
echo "Type 'delete' to confirm."
read -r -p "> " answer
[[ "$answer" == "delete" ]] || vps1_die "Confirmation mismatch. Aborted (nothing was dropped)."

#######################################
# Drop
#######################################
for DB_SELECTED in "${SELECTED[@]}"; do
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
done

echo "✔ Dropped ${#SELECTED[@]} database(s) on vps1."
