#!/usr/bin/env bash
# vps1-db-snapshot.sh — create a .bak snapshot of a vps1 database into the
# dedicated vps1 snapshots folder.
#
# Usage: vps1-db-snapshot.sh <snapshotName>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

# Prints "Size / Uncompressed / Ratio / Duration" lines from "<bytes>|<bytes>|<ms>" on stdin.
vps1_print_backup_stats() {
  awk -F'|' '
    function human(b,  u, i) {
      split("B KB MB GB TB", u, " "); i = 1
      while (b >= 1024 && i < 5) { b /= 1024; i++ }
      return (i == 1) ? sprintf("%d B", b) : sprintf("%.2f %s", b, u[i])
    }
    function dur(ms,  s) {
      s = ms / 1000
      if (s < 60) return sprintf("%.1fs", s)
      if (s < 3600) return sprintf("%dm %02ds", s / 60, s % 60)
      return sprintf("%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60)
    }
    NF >= 3 && $1 + 0 > 0 {
      printf "  Size           : %s\n", human($2)
      printf "  Uncompressed   : %s\n", human($1)
      printf "  Compression    : %.2fx\n", $1 / $2
      printf "  Duration       : %s\n", dur($3)
    }'
}

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

snapshot_path_sql="${SNAPSHOT_CONTAINER_PATH//\'/\'\'}"
SNAPSHOT_STATS="$(
  vps1_sqlcmd -h -1 -W -s '|' -Q \
    "SET NOCOUNT ON; SELECT TOP 1 CAST(bs.backup_size AS bigint), CAST(ISNULL(bs.compressed_backup_size, bs.backup_size) AS bigint), DATEDIFF(MILLISECOND, bs.backup_start_date, bs.backup_finish_date) FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id WHERE mf.physical_device_name = N'$snapshot_path_sql' AND bs.type = 'D' ORDER BY bs.backup_set_id DESC;" \
    2>/dev/null | tr -d '\r' | sed '/^$/d' | head -n 1
)" || SNAPSHOT_STATS=""

echo
echo "✔ vps1 snapshot completed"
echo "  Database       : $DB_SELECTED"
echo "  File name      : $SNAPSHOT_NAME"
echo "  Host path      : $VPS1_SNAPSHOTS_HOST_DIR/$SNAPSHOT_NAME"
echo "  Container path : $SNAPSHOT_CONTAINER_PATH"
printf '%s\n' "$SNAPSHOT_STATS" | vps1_print_backup_stats
