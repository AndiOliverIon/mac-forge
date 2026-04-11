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
# Helpers (Reused from db-fix.sh)
#######################################
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

get_dbs_list() {
    local server="$1"
    local user="$2"
    local pwd="$3"
    local trusted="$4"

    local args=('-S' "$server" '-C')
    if [[ "$trusted" == "true" ]]; then
        args+=('-E')
    else
        args+=('-U' "$user" '-P' "$pwd")
    fi

    local query="SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb', 'rdsadmin') ORDER BY name;"
    sqlcmd "${args[@]}" -h -1 -W -Q "$query" 2>/dev/null || true
}

run_sql_file() {
    local server="$1"
    local user="$2"
    local pwd="$3"
    local db="$4"
    local file="$5"
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

    # Execute silently, capture output for potential error reporting
    sqlcmd "${args[@]}" -i "$file" > /tmp/sql_exec.log 2>&1
}

#######################################
# Main Flow
#######################################

# 1. List SQL files in current directory by creation (birth) time
# Using stat -f %B for birthtime on macOS. sort -rn for newest first.
echo "Scanning for .sql files in $PWD..."
sql_files=$(stat -f "%B %N" *.sql 2>/dev/null | sort -rn | sed 's/^[0-9]* //') || true

if [[ -z "$sql_files" ]]; then
    echo "No .sql files found in the current directory."
    exit 0
fi

# 2. Select files via fzf (Multi-select enabled)
# Users can use Tab to "check" items
selected_files=$(echo "$sql_files" | fzf --multi \
    --prompt="Check SQL files (Tab: toggle, Enter: confirm) > " \
    --header="Files sorted by creation time (newest first)" \
    --height=40% --border)

if [[ -z "$selected_files" ]]; then
    echo "No files selected. Exiting."
    exit 0
fi

# 3. Select Connection
conn_options="$(get_connections_list)"
if [[ -z "$conn_options" ]]; then
    echo "No connections found in $CONFIG_FILE" >&2
    exit 1
fi

selected_conn_line="$(echo "$conn_options" | fzf --prompt="Select SQL Server > " --height=10 --border)"
if [[ -z "$selected_conn_line" ]]; then
    echo "No server selected. Exiting."
    exit 0
fi

conn_index="${selected_conn_line%%:*}"
server="$(get_connection_detail "$conn_index" "server")"
user="$(get_connection_detail "$conn_index" "user")"
pwd="$(get_connection_detail "$conn_index" "password")"
trusted="$(get_connection_detail "$conn_index" "trusted")"

# 4. Select Database
echo "Fetching databases from $server..."
dbs_list=$(get_dbs_list "$server" "$user" "$pwd" "$trusted")
if [[ -z "$dbs_list" ]]; then
    echo "Error: Could not list databases for $server." >&2
    exit 1
fi

selected_db="$(echo "$dbs_list" | fzf --prompt="Select Database > " --height=20 --border)"
if [[ -z "$selected_db" ]]; then
    echo "No database selected. Exiting."
    exit 0
fi

# 5. Confirmation
file_count=$(echo "$selected_files" | wc -l | xargs)
echo ""
echo "Target Server: $server"
echo "Target DB:     $selected_db"
echo "Files to run:  $file_count"
echo "----------------------------------------"
echo "$selected_files"
echo "----------------------------------------"
read -p "Execute these files? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# 6. Execution Loop
echo "$selected_files" | while read -r file; do
    if [[ -n "$file" ]]; then
        printf "%-50s - executing..." "$(basename "$file")"
        
        if run_sql_file "$server" "$user" "$pwd" "$selected_db" "$file" "$trusted"; then
            printf "\r%-50s - [OK]           \n" "$(basename "$file")"
        else
            printf "\r%-50s - [FAILED]       \n" "$(basename "$file")"
            echo "Error details for $file:"
            cat /tmp/sql_exec.log
            echo "----------------------------------------"
            read -p "Continue with remaining files? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Aborting."
                rm -f /tmp/sql_exec.log
                exit 1
            fi
        fi
    fi
done

echo ""
echo "All tasks completed."
rm -f /tmp/sql_exec.log
