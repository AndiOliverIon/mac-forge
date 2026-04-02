#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config-local/local-store.json"
SQLS_ROOT="$PROJECT_ROOT/sqls"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

if [[ ! -d "$SQLS_ROOT" ]]; then
    echo "Error: SQL scripts root not found at $SQLS_ROOT" >&2
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

    echo "Executing $file on $server -> $db..."
    sqlcmd "${args[@]}" -i "$file"
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

select_sql_file() {
    local current_dir="$1"
    while true; do
        local selection
        # Add EXIT option to the list
        selection=$( (ls -F "$current_dir"; echo "EXIT") | fzf --prompt="Select (Root: $(basename "$SQLS_ROOT")) > " --height=40% --border)
        
        if [[ -z "$selection" || "$selection" == "EXIT" ]]; then
            return 1
        fi

        local full_path="$current_dir/$selection"
        # Remove trailing slash for directories if added by ls -F
        full_path="${full_path%/}"

        if [[ -d "$full_path" ]]; then
            current_dir="$full_path"
        elif [[ -f "$full_path" ]]; then
            if [[ "$full_path" == *.sql ]]; then
                echo "$full_path"
                return 0
            else
                echo "Warning: Only .sql files are supported." >&2
            fi
        fi
    done
}

#######################################
# Main Flow
#######################################

# 1. Select Connection
conn_options="$(get_connections_list)"
if [[ -z "$conn_options" ]]; then
    echo "No connections found in $CONFIG_FILE" >&2
    exit 1
fi

selected_conn_line="$(echo "$conn_options" | fzf --prompt="Select Connection > " --height=10 --border)"
if [[ -z "$selected_conn_line" ]]; then
    exit 0
fi

conn_index="${selected_conn_line%%:*}"
server="$(get_connection_detail "$conn_index" "server")"
user="$(get_connection_detail "$conn_index" "user")"
pwd="$(get_connection_detail "$conn_index" "password")"
trusted="$(get_connection_detail "$conn_index" "trusted")"

# 2. Select Database
dbs_list=$(get_dbs_list "$server" "$user" "$pwd" "$trusted")
if [[ -z "$dbs_list" ]]; then
    echo "Error: Could not list databases." >&2
    exit 1
fi

selected_db="$(echo "$dbs_list" | fzf --prompt="Select Database > " --height=20 --border)"
if [[ -z "$selected_db" ]]; then
    exit 0
fi

# 3. Select and Execute SQL Scripts Loop
echo "==> Select SQL scripts to run (ESC to exit):"
while true; do
    selected_file=$(select_sql_file "$SQLS_ROOT" || true)
    
    if [[ -z "$selected_file" ]]; then
        echo "Exiting."
        break
    fi

    run_sql_file "$server" "$user" "$pwd" "$selected_db" "$selected_file" "$trusted"
    echo "----------------------------------------"
done
