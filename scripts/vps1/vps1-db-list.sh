#!/opt/homebrew/bin/bash
# vps1-db-list.sh — show all installed databases and all available snapshots
# on vps1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd sqlcmd
vps1_require_cmd ssh
vps1_load_connection

#######################################
# Installed databases
#######################################
echo "════════════════════════════════════════════════════════════"
echo " Installed databases on vps1 ($VPS1_SQL_SERVER)"
echo "════════════════════════════════════════════════════════════"
db_rows="$(
  vps1_sqlcmd -h -1 -W -s '|' -Q "
SET NOCOUNT ON;
SELECT
  d.name,
  CONVERT(varchar(19), d.create_date, 120),
  d.state_desc,
  CAST(CAST(SUM(mf.size) * 8.0 / 1024.0 AS decimal(10,1)) AS varchar(20))
FROM sys.databases d
JOIN sys.master_files mf ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.create_date, d.state_desc
ORDER BY d.name;" 2>/dev/null | tr -d '\r' | sed '/^$/d'
)"

if [[ -z "${db_rows//$'\n'/}" ]]; then
  echo "  (none)"
else
  printf '  %-32s %-19s %-10s %10s\n' "NAME" "CREATED" "STATE" "SIZE(MB)"
  printf '  %-32s %-19s %-10s %10s\n' "--------------------------------" "-------------------" "----------" "----------"
  while IFS='|' read -r name created state size; do
    [[ -n "$name" ]] || continue
    printf '  %-32s %-19s %-10s %10s\n' "$name" "$created" "$state" "$size"
  done <<< "$db_rows"
fi

#######################################
# Available snapshots
#######################################
echo
echo "════════════════════════════════════════════════════════════"
echo " Available snapshots on vps1 ($VPS1_SNAPSHOTS_HOST_DIR)"
echo "════════════════════════════════════════════════════════════"
snap_rows="$(
  vps1_ssh "find '$VPS1_SNAPSHOTS_HOST_DIR' -maxdepth 1 -type f -iname '*.bak' -printf '%f\t%TY-%Tm-%Td %TH:%TM\t%s\n' 2>/dev/null | sort -k2"
)"

if [[ -z "${snap_rows//$'\n'/}" ]]; then
  echo "  (none)"
else
  printf '  %-40s %-17s %10s\n' "FILE" "MODIFIED" "SIZE(MB)"
  printf '  %-40s %-17s %10s\n' "----------------------------------------" "-----------------" "----------"
  while IFS=$'\t' read -r fname mtime bytes; do
    [[ -n "$fname" ]] || continue
    mb="$(awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1048576}')"
    printf '  %-40s %-17s %10s\n' "$fname" "$mtime" "$mb"
  done <<< "$snap_rows"
fi
echo
