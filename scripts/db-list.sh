#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/forge.sh"

if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$FORGE_SECRETS_FILE"
fi

FORGE_SQL_HOST="${FORGE_SQL_HOST:-localhost}"
FORGE_SQL_USER="${FORGE_SQL_USER:-sa}"

command -v sqlcmd >/dev/null 2>&1 || {
	echo "Required command 'sqlcmd' not found." >&2
	exit 1
}

: "${FORGE_SQL_PORT:?FORGE_SQL_PORT must be set in forge.sh}"
: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set in forge-secrets.sh}"

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

echo "Local SQL databases (${FORGE_SQL_HOST},${FORGE_SQL_PORT})"
echo

sqlcmd \
	-S "${FORGE_SQL_HOST},${FORGE_SQL_PORT}" \
	-U "$FORGE_SQL_USER" \
	-P "$FORGE_SQL_SA_PASSWORD" \
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
