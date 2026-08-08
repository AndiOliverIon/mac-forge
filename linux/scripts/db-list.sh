#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/forge.sh"

forge_require_cmd sqlcmd
forge_assert_sensitive_config

host_port="$(forge_get docker.host_port)"
sql_user="$(forge_get docker.sql_user)"
sa_password="$(forge_get sql.sa_password)"

query="
SET NOCOUNT ON;

SELECT
    d.name AS DatabaseName,
    d.state_desc AS StateDescription,
    d.recovery_model_desc AS RecoveryModel,
    COALESCE(SUM(CASE WHEN mf.type = 0 THEN CONVERT(BIGINT, mf.size) * 8192 ELSE 0 END), 0) AS DataBytes,
    COALESCE(SUM(CASE WHEN mf.type = 1 THEN CONVERT(BIGINT, mf.size) * 8192 ELSE 0 END), 0) AS LogBytes,
    COALESCE(SUM(CONVERT(BIGINT, mf.size) * 8192), 0) AS TotalBytes
FROM sys.databases AS d
LEFT JOIN sys.master_files AS mf
    ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY
    d.name,
    d.state_desc,
    d.recovery_model_desc
ORDER BY
    TotalBytes DESC,
    d.name;
"

echo "Local SQL databases (localhost,${host_port})"
echo

sqlcmd \
  -S "localhost,${host_port}" \
  -U "$sql_user" \
  -P "$sa_password" \
  -C -b -h -1 -W -s '|' -w 65535 \
  -Q "$query" |
  tr -d '\r' |
  awk -F '|' '
function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    return value
}

function friendly(bytes, value) {
    value = bytes + 0
    if (value >= 1099511627776) return sprintf("%.2f TB", value / 1099511627776)
    if (value >= 1073741824)    return sprintf("%.2f GB", value / 1073741824)
    if (value >= 1048576)       return sprintf("%.1f MB", value / 1048576)
    if (value >= 1024)          return sprintf("%.1f KB", value / 1024)
    return sprintf("%d B", value)
}

BEGIN {
    printf "%-42s %10s %10s %10s  %-10s %-8s\n", "DATABASE", "TOTAL", "DATA", "LOG", "STATE", "RECOVERY"
    printf "%-42s %10s %10s %10s  %-10s %-8s\n", "------------------------------------------", "----------", "----------", "----------", "----------", "--------"
}

NF >= 6 {
    name = trim($1)
    state = trim($2)
    recovery = trim($3)
    data = trim($4)
    log_bytes = trim($5)
    total = trim($6)

    printf "%-42s %10s %10s %10s  %-10s %-8s\n", name, friendly(total), friendly(data), friendly(log_bytes), state, recovery
    total_bytes += total
    count++
}

END {
    if (count == 0) {
        print "No user databases found."
    } else {
        printf "\n%d database%s · %s allocated\n", count, count == 1 ? "" : "s", friendly(total_bytes)
    }
}
'
