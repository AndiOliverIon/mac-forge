#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config-local/local-store.json"

die() {
	echo "Error: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

for cmd in fzf sqlcmd python3 find sort sed grep; do
	require_cmd "$cmd"
done

[[ -f "$CONFIG_FILE" ]] || die "Configuration file not found at $CONFIG_FILE"

get_connections_list() {
	python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

for index, conn in enumerate(data.get("connections", [])):
    display = conn.get("display") or "Unknown"
    print(f"{index}: {display}")
PY
}

get_connection_detail() {
	local index="$1"
	local field="$2"

	python3 - "$CONFIG_FILE" "$index" "$field" <<'PY'
import json
import sys

config_file, index, field = sys.argv[1], int(sys.argv[2]), sys.argv[3]

with open(config_file, "r", encoding="utf-8") as handle:
    data = json.load(handle)

value = data["connections"][index].get(field, "")
if value is True:
    print("true")
elif value is False:
    print("false")
else:
    print(value)
PY
}

run_sql_file() {
	local server="$1"
	local user="$2"
	local password="$3"
	local trusted="$4"
	local file="$5"

	local -a args=(-S "$server" -C -b)

	if [[ "$trusted" == "true" ]]; then
		args+=(-E)
	else
		[[ -n "$user" ]] || die "Selected connection requires a user."
		args+=(-U "$user" -P "$password")
	fi

	sqlcmd "${args[@]}" -i "$file"
}

sql_files="$(
	find . -maxdepth 1 -type f -iname "*.sql" -print |
		sed "s|^\./||" |
		sort
)"

[[ -n "${sql_files//$'\n'/}" ]] || die "No .sql files found in current folder: $PWD"

ordered_files=""
remaining_files="$sql_files"

while true; do
	selected_summary="$(
		if [[ -n "${ordered_files//$'\n'/}" ]]; then
			printf '%s\n' "$ordered_files" |
				sed '/^$/d' |
				sed '=' |
				sed 'N;s/\n/. /'
		else
			printf 'None selected yet.'
		fi
	)"

	if [[ -n "${ordered_files//$'\n'/}" ]]; then
		choice_list="$(
			printf 'DONE\n'
			printf '%s\n' "$remaining_files"
		)"
	else
		choice_list="$remaining_files"
	fi

	selected_file="$(
		printf '%s\n' "$choice_list" |
			fzf --no-sort \
				--prompt="Select next SQL script > " \
				--header="Selected order:
$selected_summary

Pick scripts one by one in execution order. Choose DONE when finished." \
				--height=45% --border
	)" || die "No SQL scripts selected."

	if [[ "$selected_file" == "DONE" ]]; then
		break
	fi

	ordered_files="${ordered_files}${selected_file}"$'\n'
	remaining_files="$(
		printf '%s\n' "$remaining_files" |
			grep -Fxv -- "$selected_file" || true
	)"

	if [[ -z "${remaining_files//$'\n'/}" ]]; then
		break
	fi
done

[[ -n "${ordered_files//$'\n'/}" ]] || die "No SQL scripts selected."

conn_options="$(get_connections_list)"
[[ -n "${conn_options//$'\n'/}" ]] || die "No connections found in $CONFIG_FILE"

selected_conn_line="$(
	printf '%s\n' "$conn_options" |
		fzf --prompt="Select SQL connection > " --height=10 --border
)" || die "No SQL connection selected."

conn_index="${selected_conn_line%%:*}"
server="$(get_connection_detail "$conn_index" "server")"
user="$(get_connection_detail "$conn_index" "user")"
password="$(get_connection_detail "$conn_index" "password")"
trusted="$(get_connection_detail "$conn_index" "trusted")"

[[ -n "$server" ]] || die "Selected connection has no server."

echo
echo "Target connection: $server"
echo "Scripts to run:"
while IFS= read -r file; do
	[[ -n "$file" ]] || continue
	echo "  - $file"
done <<<"$ordered_files"
echo

read -r -p "Run selected SQL scripts in this order? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."

while IFS= read -r file; do
	[[ -n "$file" ]] || continue
	full_path="$PWD/$file"
	echo
	echo "Running: $file"

	if run_sql_file "$server" "$user" "$password" "$trusted" "$full_path"; then
		echo "OK: $file"
	else
		echo "FAILED: $file" >&2
		exit 1
	fi
done <<<"$ordered_files"

echo
echo "All selected SQL scripts completed successfully."
