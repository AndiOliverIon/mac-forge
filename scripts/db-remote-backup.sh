#!/opt/homebrew/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/scripts/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/scripts/forge.sh"
fi

die() { echo "✖ $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

require_cmd fzf
require_cmd jq
require_cmd sqlcmd

SQLCMD_BIN="${FORGE_SQLCMD_BIN:-$(command -v sqlcmd)}"
SQLCMD_GODEBUG="${FORGE_SQLCMD_GODEBUG:-x509negativeserial=1}"

LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$HOME/mac-forge/config-local}/local-store.json"
[[ -f "$LOCAL_STORE_FILE" ]] || die "Missing local store file: $LOCAL_STORE_FILE"

selection_tsv="$(
  jq -r '
    (.remote_sql // [])
    | to_entries[]?
    | select(
        .value.name != null and
        .value.user != null and
        .value.pwd != null and
        .value.backuppath != null and
        ((.value.serverurl != null) or (.value.host != null))
      )
    | [
        (.key|tostring),
        .value.name,
        (.value.serverurl // ""),
        (.value.host // ""),
        (.value.port // ""),
        (.value.instance // ""),
        (.value.instance_strict // false),
        .value.user,
        .value.pwd,
        .value.backuppath
      ]
    | @tsv
  ' "$LOCAL_STORE_FILE"
)"

[[ -n "${selection_tsv//$'\n'/}" ]] || die "No valid entries under remote_sql in $LOCAL_STORE_FILE"

chosen_line="$(
  printf '%s\n' "$selection_tsv" \
    | fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=2,3,4,5,6,10 --height=65%
)" || die "No remote SQL target selected."

server_name="$(printf '%s' "$chosen_line" | cut -f2)"
server_url="$(printf '%s' "$chosen_line" | cut -f3)"
server_host="$(printf '%s' "$chosen_line" | cut -f4)"
server_port="$(printf '%s' "$chosen_line" | cut -f5)"
server_instance="$(printf '%s' "$chosen_line" | cut -f6)"
instance_strict_raw="$(printf '%s' "$chosen_line" | cut -f7)"
server_user="$(printf '%s' "$chosen_line" | cut -f8)"
server_pwd="$(printf '%s' "$chosen_line" | cut -f9)"
backup_dir="$(printf '%s' "$chosen_line" | cut -f10-)"

[[ -n "$server_user" && -n "$server_pwd" && -n "$backup_dir" ]] ||
  die "Selected remote_sql entry is missing required fields."

connect_server=""
expected_instance=""

if [[ -n "$server_host" ]]; then
  if [[ -n "$server_port" ]]; then
    connect_server="tcp:${server_host},${server_port}"
  elif [[ -n "$server_instance" ]]; then
    connect_server="${server_host}\\${server_instance}"
  else
    connect_server="$server_host"
  fi

  if [[ -n "$server_instance" ]]; then
    expected_instance="$server_instance"
  fi
else
  connect_server="$server_url"

  if [[ "$connect_server" == *,*\\* || "$connect_server" == *\\*,* ]]; then
    die "remote_sql entry '$server_name' has invalid serverurl '$connect_server'. Use structured fields host/port/instance instead."
  fi
fi

[[ -n "$connect_server" ]] || die "Selected remote_sql entry does not define a usable server address."

run_sqlcmd_raw() {
  if [[ -n "$SQLCMD_GODEBUG" ]]; then
    GODEBUG="$SQLCMD_GODEBUG" "$SQLCMD_BIN" "$@"
  else
    "$SQLCMD_BIN" "$@"
  fi
}

run_sqlcmd_capture() {
  local query="$1"
  run_sqlcmd_raw \
    -S "$connect_server" \
    -U "$server_user" \
    -P "$server_pwd" \
    -C \
    -b \
    -h -1 \
    -W \
    -Q "$query" \
    2>&1
}

is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

if [[ -n "$expected_instance" ]]; then
  if ! instance_raw="$(run_sqlcmd_capture "SET NOCOUNT ON; SELECT COALESCE(CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128)), N'MSSQLSERVER');")"; then
    instance_err="$(printf '%s' "$instance_raw" | tr -d '\r' | sed '/^$/d' | tail -n 8)"
    die "Failed to verify SQL instance on '$server_name' ($connect_server). sqlcmd output: ${instance_err:-<empty>}"
  fi

  instance_actual="$(printf '%s' "$instance_raw" | tr -d '\r' | sed '/^$/d' | head -n 1)"
  [[ -n "$instance_actual" ]] || die "Connected, but could not read SQL instance name."

  if [[ "${instance_actual,,}" != "${expected_instance,,}" ]]; then
    if is_truthy "$instance_strict_raw"; then
      die "Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'."
    fi
    echo "⚠ Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'." >&2
    echo "  Continuing because instance_strict is false." >&2
  fi
fi

if ! db_list_raw="$(run_sqlcmd_capture "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;")"; then
  db_list_err="$(printf '%s' "$db_list_raw" | tr -d '\r' | sed '/^$/d' | tail -n 8)"
  die "Failed to list databases on '$server_name' ($connect_server). sqlcmd output: ${db_list_err:-<empty>}"
fi

db_list="$(printf '%s' "$db_list_raw" | tr -d '\r' | sed '/^$/d')"
[[ -n "${db_list//$'\n'/}" ]] || die "No user databases found on '$server_name'."

selected_db="$(
  printf '%s\n' "$db_list" | fzf --prompt='Database > ' --height=45% --border
)" || die "No database selected."

default_backup_name="${selected_db}_$(date +%Y%m%d).bak"

echo "Target      : $server_name ($connect_server)"
if [[ -n "$expected_instance" ]]; then
  echo "Instance    : $expected_instance"
fi
echo "Database    : $selected_db"
echo "Backup path : $backup_dir"
echo
read -r -p "Backup file name [$default_backup_name]: " backup_name
backup_name="${backup_name:-$default_backup_name}"
[[ -n "$backup_name" ]] || die "Backup file name cannot be empty."

case "$backup_name" in
  *.bak|*.BAK) ;;
  *) backup_name="${backup_name}.bak" ;;
esac

join_backup_path() {
  local dir="$1"
  local file="$2"

  if [[ "$dir" == */ || "$dir" == *\\ ]]; then
    printf '%s%s' "$dir" "$file"
    return
  fi

  if [[ "$dir" == *\\* && "$dir" != */* ]]; then
    printf '%s\\%s' "$dir" "$file"
  else
    printf '%s/%s' "$dir" "$file"
  fi
}

escape_tsql_string() {
  local s="$1"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

tsql_ident() {
  local name="$1"
  name="${name//]/]]}"
  printf '[%s]' "$name"
}

backup_full_path="$(join_backup_path "$backup_dir" "$backup_name")"
backup_full_path_sql="$(escape_tsql_string "$backup_full_path")"
db_ident="$(tsql_ident "$selected_db")"

if ! backup_raw="$(
  run_sqlcmd_raw \
    -S "$connect_server" \
    -U "$server_user" \
    -P "$server_pwd" \
    -C \
    -b \
    -Q "BACKUP DATABASE $db_ident TO DISK = N'$backup_full_path_sql' WITH INIT, COPY_ONLY, COMPRESSION, STATS = 5;" \
    2>&1
)"; then
  backup_err="$(printf '%s' "$backup_raw" | tr -d '\r' | sed '/^$/d' | tail -n 12)"
  die "Backup failed on '$server_name' ($connect_server). sqlcmd output: ${backup_err:-<empty>}"
fi

echo "$backup_raw" | sed '/^$/d'
echo
echo "✔ Backup created:"
echo "  $backup_full_path"
