#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config-local/local-store.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

#######################################
# Dependencies
#######################################
for cmd in fzf sqlcmd python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found." >&2
        exit 1
    fi
done

#######################################
# Helpers
#######################################
# Extract connection list for fzf
# Format: "Index: DisplayName"
get_connections_list() {
    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    for i, conn in enumerate(data.get('connections', [])):
        print(f\"{i}: {conn.get('display', 'Unknown')}\")
except Exception as e:
    sys.exit(1)
"
}

# Get connection details by index
get_connection_detail() {
    local index="$1"
    local field="$2"
    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    conn = data['connections'][int($index)]
    val = conn.get('$field', '')
    if val is True: print('true')
    elif val is False: print('false')
    else: print(val)
except:
    pass
"
}

get_cleanup_tables() {
    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    for item in data.get('cleanup_tables', []):
        print(f\"{item.get('schema')}|{item.get('table')}|{item.get('method')}\")
except:
    pass
"
}

run_sql() {
    local server="$1"
    local user="$2"
    local pwd="$3"
    local db="$4" # Can be empty for server-level queries
    local query="$5"
    local trusted="$6"

    local args=('-S' "$server" '-C')
    
    if [[ "$trusted" == "true" ]]; then
        args+=('-E')
    else
        args+=('-U' "$user" '-P' "$pwd")
    fi

    if [[ -n "$db" ]]; then
        args+=('-d' "$db")
    fi

    # Suppress headers/footers for cleaner output when fetching data
    # -h -1 : no headers
    # -W : remove trailing spaces
    sqlcmd "${args[@]}" -h -1 -W -Q "$query"
}

#######################################
# Main Flow
#######################################

# 1. Select Connection
echo "==> Select SQL Connection:"
conn_options="$(get_connections_list)"
if [[ -z "$conn_options" ]]; then
    echo "No connections found in $CONFIG_FILE" >&2
    exit 1
fi

selected_conn_line="$(echo "$conn_options" | fzf --height=10 --border)"
if [[ -z "$selected_conn_line" ]]; then
    echo "No connection selected."
    exit 1
fi

conn_index="${selected_conn_line%%:*}"
server="$(get_connection_detail "$conn_index" "server")"
user="$(get_connection_detail "$conn_index" "user")"
pwd="$(get_connection_detail "$conn_index" "password")"
trusted="$(get_connection_detail "$conn_index" "trusted")"

echo "Using: $server (User: ${user:-Integrated})"

# 2. Select Database
echo "==> Fetching Databases..."
# Filter out system databases
dbs_query="SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb', 'rdsadmin') ORDER BY name;"

dbs_list=$(run_sql "$server" "$user" "$pwd" "" "$dbs_query" "$trusted" 2>/dev/null || true)

if [[ -z "$dbs_list" ]]; then
    echo "Error: Could not list databases. Check connection details." >&2
    exit 1
fi

echo "==> Select Database to Optimize:"
selected_db="$(echo "$dbs_list" | fzf --height=20 --border)"

if [[ -z "$selected_db" ]]; then
    echo "No database selected."
    exit 1
fi

echo "Selected Database: $selected_db"
read -r -p "Are you sure you want to optimize (Data Loss Possible)? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# 3. Optimize

# 3.1 Simple Recovery
echo "--> Setting Recovery Model to SIMPLE..."
run_sql "$server" "$user" "$pwd" "master" "ALTER DATABASE [$selected_db] SET RECOVERY SIMPLE WITH NO_WAIT;" "$trusted"

# 3.2 Cleanup Tables
echo "--> Processing Cleanup Rules..."
IFS=$'\n'
for rule in $(get_cleanup_tables);
do
    schema="$(echo "$rule" | cut -d'|' -f1)"
    table="$(echo "$rule" | cut -d'|' -f2)"
    method="$(echo "$rule" | cut -d'|' -f3)" # truncate or delete

    # Check existence
    check_query="SET NOCOUNT ON; SELECT 1 FROM information_schema.tables WHERE table_schema = '$schema' AND table_name = '$table'"
    exists=$(run_sql "$server" "$user" "$pwd" "$selected_db" "$check_query" "$trusted" 2>/dev/null || true)

    if [[ -n "$exists" ]]; then
        echo "    Found [$schema].[$table] -> $method"
        if [[ "$method" == "truncate" ]]; then
            run_sql "$server" "$user" "$pwd" "$selected_db" "TRUNCATE TABLE [$schema].[$table];" "$trusted"
        elif [[ "$method" == "delete" ]]; then
             run_sql "$server" "$user" "$pwd" "$selected_db" "DELETE FROM [$schema].[$table];" "$trusted"
        else
            echo "    Unknown method '$method', skipping."
        fi
    else
        echo "    Skipping [$schema].[$table] (Not found)"
    fi
done
unset IFS

# 3.3 Shrink
echo "--> Shrinking Database..."
run_sql "$server" "$user" "$pwd" "$selected_db" "DBCC SHRINKDATABASE(0);" "$trusted"

echo "==> Optimization Complete for [$selected_db]."
