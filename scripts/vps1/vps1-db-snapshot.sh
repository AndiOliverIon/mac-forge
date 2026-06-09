#!/opt/homebrew/bin/bash
# vps1-db-snapshot.sh — create a .bak snapshot of a vps1 database into the
# dedicated vps1 snapshots folder.
#
# Usage: vps1-db-snapshot.sh <snapshotName>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Input
#######################################
[[ $# -eq 1 ]] || vps1_die "Usage: vps1-db-snapshot.sh <snapshotName>"
SNAPSHOT_SUFFIX="$1"

#######################################
# Preconditions
#######################################
vps1_require_cmd sqlcmd
vps1_require_cmd fzf
vps1_require_cmd ssh
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

DB_SELECTED="$(printf '%s\n' "${DB_LIST[@]}" | fzf --prompt='Select vps1 database to snapshot > ')" \
  || vps1_die "No database selected."
echo "Selected database: $DB_SELECTED"

#######################################
# Backup into the dedicated snapshots folder
#######################################
SNAPSHOT_NAME="${DB_SELECTED}_${SNAPSHOT_SUFFIX}.bak"
SNAPSHOT_CONTAINER_PATH="${VPS1_SNAPSHOTS_CONTAINER_DIR}/${SNAPSHOT_NAME}"

vps1_log_step "Creating vps1 snapshot: $SNAPSHOT_NAME"
vps1_sqlcmd -b -Q \
  "BACKUP DATABASE [$DB_SELECTED] TO DISK = N'$SNAPSHOT_CONTAINER_PATH' WITH INIT, STATS = 5;"

vps1_chmod_snapshot "$SNAPSHOT_NAME"
vps1_ssh "test -f '$VPS1_SNAPSHOTS_HOST_DIR/$SNAPSHOT_NAME'" \
  || vps1_die "Backup reported success but snapshot not found on vps1: $VPS1_SNAPSHOTS_HOST_DIR/$SNAPSHOT_NAME"

echo
echo "✔ vps1 snapshot completed"
echo "  Database       : $DB_SELECTED"
echo "  File name      : $SNAPSHOT_NAME"
echo "  Host path      : $VPS1_SNAPSHOTS_HOST_DIR/$SNAPSHOT_NAME"
echo "  Container path : $SNAPSHOT_CONTAINER_PATH"
