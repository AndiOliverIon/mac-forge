#!/opt/homebrew/bin/bash
# db-remote-restore.sh (alias: rdbr)
#
# Restore a .bak from a configured remote SQL Server target back into that
# same server. Mirrors db-remote-backup.sh (rdbsn) for server selection, then:
#   1. lists candidate .bak snapshots in the server's backup path,
#   2. lets you pick an existing database (override) or type a new name (clone),
#   3. restores with explicit WITH MOVE to database-specific physical files.
#
# Safety: when cloning A -> new B, SQL Server would otherwise reuse A's physical
# file paths embedded in the backup, which can damage A. This script always
# remaps every file with WITH MOVE and refuses to run (without touching A) if
# any target .mdf/.ldf path is already used by another database or already
# exists on disk un-owned by the target database.
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

#######################################
# Small helpers
#######################################
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
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

is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

#######################################
# Select remote SQL target (same source as rdbsn)
#######################################
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

#######################################
# sqlcmd runners
#######################################
run_sqlcmd_raw() {
  if [[ -n "$SQLCMD_GODEBUG" ]]; then
    GODEBUG="$SQLCMD_GODEBUG" "$SQLCMD_BIN" "$@"
  else
    "$SQLCMD_BIN" "$@"
  fi
}

# Run a query, die on error, return raw rows (CR stripped, blank lines dropped).
run_q_rows() {
  local sep="$1" query="$2" out rc
  set +e
  out="$(
    run_sqlcmd_raw \
      -S "$connect_server" -U "$server_user" -P "$server_pwd" \
      -C -b -h -1 -W -s "$sep" -w 65535 \
      -Q "$query" 2>&1
  )"
  rc=$?
  set -e
  if ((rc != 0)); then
    die "SQL query failed on '$server_name' ($connect_server):"$'\n'"$(printf '%s' "$out" | tr -d '\r' | sed '/^$/d' | tail -n 12)"
  fi
  printf '%s' "$out" | tr -d '\r' | sed '/^$/d'
}

# Run a scalar query, return first non-empty value (may be empty).
run_q_scalar() {
  run_q_rows '|' "$1" | head -n 1
}

#######################################
# Verify instance (same guard as rdbsn)
#######################################
if [[ -n "$expected_instance" ]]; then
  instance_actual="$(run_q_scalar "SET NOCOUNT ON; SELECT COALESCE(CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128)), N'MSSQLSERVER');")"
  [[ -n "$instance_actual" ]] || die "Connected, but could not read SQL instance name."

  if [[ "${instance_actual,,}" != "${expected_instance,,}" ]]; then
    if is_truthy "$instance_strict_raw"; then
      die "Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'."
    fi
    echo "⚠ Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'." >&2
    echo "  Continuing because instance_strict is false." >&2
  fi
fi

#######################################
# List candidate .bak snapshots in backup_dir, newest first
#######################################
backup_dir_sql="$(escape_tsql_string "$backup_dir")"
dirlist_raw="$(run_q_rows '|' "SET NOCOUNT ON; SELECT file_or_directory_name FROM sys.dm_os_enumerate_filesystem(N'$backup_dir_sql', N'*.bak') WHERE is_directory = 0 ORDER BY last_write_time DESC;")"

mapfile -t bak_files < <(
  printf '%s\n' "$dirlist_raw" | awk '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { name = trim($0); if (tolower(name) ~ /\.bak$/) print name }
  '
)

((${#bak_files[@]} > 0)) || die "No .bak files found in backup path on '$server_name': $backup_dir"

selected_bak="$(
  printf '%s\n' "${bak_files[@]}" | fzf --prompt="Snapshot on $server_name (newest first) > " --height=60% --reverse
)" || die "No snapshot selected."

# Join backup_dir + filename respecting path style.
if [[ "$backup_dir" == *'\'* && "$backup_dir" != */* ]]; then
  bak_full_path="${backup_dir%\\}\\${selected_bak}"
else
  bak_full_path="${backup_dir%/}/${selected_bak}"
fi
bak_full_path_sql="$(escape_tsql_string "$bak_full_path")"

#######################################
# Choose target database (existing = override, new = clone)
#######################################
db_list="$(run_q_rows '|' "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;")"

# Default suggestion derived from snapshot filename.
default_db_name="${selected_bak%.*}"
default_db_name="${default_db_name%%.*}"
default_db_name="${default_db_name%%_*}"

NEW_LABEL="➕ Choose a new one"
menu="$(printf '%s\n' "$NEW_LABEL"; printf '%s\n' "$db_list")"

choice="$(
  printf '%s' "$menu" \
    | fzf --prompt='Target DB (existing = OVERRIDE) > ' --height=50% --reverse
)" || die "Cancelled."

if [[ "$choice" == "$NEW_LABEL" ]]; then
  read -r -p "New database name [$default_db_name]: " db_name
  db_name="${db_name:-$default_db_name}"
else
  db_name="$choice"
fi
db_name="$(trim "$db_name")"
[[ -n "$db_name" ]] || die "Database name cannot be empty."

# Reject characters that are unsafe in physical file paths.
case "$db_name" in
  *[/\\:\*\?\"\<\>\|]*) die "Database name '$db_name' contains characters not allowed for file paths." ;;
esac

db_name_sql="$(escape_tsql_string "$db_name")"
db_ident="$(tsql_ident "$db_name")"

db_exists="$(run_q_scalar "SET NOCOUNT ON; SELECT 1 FROM sys.databases WHERE name = N'$db_name_sql';")"
is_existing=false
[[ "$db_exists" == "1" ]] && is_existing=true

#######################################
# Discover default data/log directories on the server
#######################################
data_dir="$(run_q_scalar "SET NOCOUNT ON; SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath'));")"
log_dir="$(run_q_scalar "SET NOCOUNT ON; SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultLogPath'));")"

master_mdf=""
if [[ -z "$data_dir" || "$data_dir" == "NULL" || -z "$log_dir" || "$log_dir" == "NULL" ]]; then
  master_mdf="$(run_q_scalar "SET NOCOUNT ON; SELECT physical_name FROM sys.master_files WHERE database_id = 1 AND type = 0;")"
  [[ -n "$master_mdf" && "$master_mdf" != "NULL" ]] || die "Could not determine default file directories on '$server_name'."
fi

dir_of() {
  local p="$1"
  if [[ "$p" == *'\'* && "$p" != */* ]]; then
    printf '%s' "${p%\\*}"
  else
    printf '%s' "${p%/*}"
  fi
}

if [[ -z "$data_dir" || "$data_dir" == "NULL" ]]; then data_dir="$(dir_of "$master_mdf")"; fi
if [[ -z "$log_dir"  || "$log_dir"  == "NULL" ]]; then log_dir="$(dir_of "$master_mdf")"; fi

# Strip trailing separators and pick a separator style.
data_dir="${data_dir%/}"; data_dir="${data_dir%\\}"
log_dir="${log_dir%/}";   log_dir="${log_dir%\\}"
if [[ "$data_dir" == *'\'* && "$data_dir" != */* ]]; then sep='\'; else sep='/'; fi

#######################################
# Read FILELISTONLY and compute target physical files
#######################################
filelist_raw="$(run_q_rows '|' "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$bak_full_path_sql';")"
[[ -n "${filelist_raw//$'\n'/}" ]] || die "FILELISTONLY returned no output for: $bak_full_path"

declare -a move_lines=()
declare -a targets=()
data_idx=0
log_idx=0

while IFS= read -r line; do
  IFS='|' read -r -a cols <<< "$line"
  ((${#cols[@]} >= 3)) || continue
  logical="$(trim "${cols[0]}")"
  ftype="$(trim "${cols[2]}")"
  [[ -n "$logical" ]] || continue

  case "$ftype" in
    D)
      data_idx=$((data_idx + 1))
      if ((data_idx == 1)); then fname="${db_name}.mdf"; else fname="${db_name}_${data_idx}.mdf"; fi
      target="${data_dir}${sep}${fname}"
      ;;
    L)
      log_idx=$((log_idx + 1))
      if ((log_idx == 1)); then fname="${db_name}_log.ldf"; else fname="${db_name}_log_${log_idx}.ldf"; fi
      target="${log_dir}${sep}${fname}"
      ;;
    *)
      die "Backup contains an unsupported file type ('$ftype' for '$logical'). Refusing to restore to avoid relocating files unsafely."
      ;;
  esac

  targets+=("$target")
  move_lines+=("  MOVE N'$(escape_tsql_string "$logical")' TO N'$(escape_tsql_string "$target")'")
done <<< "$filelist_raw"

((${#move_lines[@]} > 0)) || die "Could not build any MOVE clauses from the backup."
((data_idx >= 1)) || die "Backup has no data file; aborting."

move_clauses="$(printf '%s,\n' "${move_lines[@]}")"
move_clauses="${move_clauses%,}"

#######################################
# SAFETY: ensure no target path collides with another database / foreign file
#######################################
echo
echo "Verifying target file paths are safe..."
for t in "${targets[@]}"; do
  t_sql="$(escape_tsql_string "$t")"

  owner="$(run_q_scalar "SET NOCOUNT ON; SELECT DB_NAME(database_id) FROM sys.master_files WHERE LOWER(physical_name) = LOWER(N'$t_sql');")"
  exists="$(run_q_scalar "SET NOCOUNT ON; DECLARE @e int; EXEC master.dbo.xp_fileexist N'$t_sql', @e OUTPUT; SELECT @e;")"

  if [[ -n "$owner" && "${owner,,}" != "${db_name,,}" ]]; then
    die "Target file '$t' is in use by database '$owner'. Refusing to restore '$db_name' so '$owner' is not damaged."
  fi

  if [[ "$exists" == "1" && ( -z "$owner" || "${owner,,}" != "${db_name,,}" ) ]]; then
    die "Target file '$t' already exists on disk and is not owned by '$db_name'. Refusing (it may belong to another database)."
  fi
done
echo "✔ Target paths are clear."

#######################################
# Summary + confirmation
#######################################
echo
echo "Server      : $server_name ($connect_server)"
[[ -n "$expected_instance" ]] && echo "Instance    : $expected_instance"
echo "Snapshot    : $bak_full_path"
if $is_existing; then
  echo "Database    : $db_name  (EXISTING — will be OVERWRITTEN)"
else
  echo "Database    : $db_name  (NEW — will be created)"
fi
echo "Data files  -> $data_dir"
echo "Log files   -> $log_dir"
echo

if $is_existing; then
  read -r -p "Type the database name '$db_name' to confirm OVERWRITE: " confirm
  [[ "$confirm" == "$db_name" ]] || die "Confirmation did not match. Aborted."
else
  read -r -p "Create and restore new database '$db_name'? [y/N]: " confirm
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || die "Aborted."
fi

#######################################
# Build restore script
#######################################
if $is_existing; then
  pre_sql="  IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name_sql')
  BEGIN
    DECLARE @state nvarchar(60) = (SELECT state_desc FROM sys.databases WHERE name = N'$db_name_sql');
    IF @state = N'RESTORING'
    BEGIN
      BEGIN TRY
        RESTORE DATABASE $db_ident WITH RECOVERY;
      END TRY
      BEGIN CATCH
      END CATCH
    END;
    IF DB_ID(N'$db_name_sql') IS NOT NULL
      ALTER DATABASE $db_ident SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  END;"
  with_replace="    REPLACE,"
  post_sql="  IF DB_ID(N'$db_name_sql') IS NOT NULL
    ALTER DATABASE $db_ident SET MULTI_USER;"
else
  pre_sql=""
  with_replace=""
  post_sql=""
fi

echo
echo "-> Restoring [$db_name] on $server_name from: $bak_full_path"

set +e
restore_out="$(
  run_sqlcmd_raw \
    -S "$connect_server" -U "$server_user" -P "$server_pwd" \
    -C -b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
$pre_sql

  RESTORE DATABASE $db_ident
  FROM DISK = N'$bak_full_path_sql'
  WITH
$with_replace
    RECOVERY,
    STATS = 5,
$move_clauses;

$post_sql
END TRY
BEGIN CATCH
  DECLARE
    @num int = ERROR_NUMBER(),
    @sev int = ERROR_SEVERITY(),
    @st  int = ERROR_STATE(),
    @ln  int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('RESTORE FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH
SQL_EOF
)"
restore_rc=$?
set -e

printf '%s\n' "$restore_out" | tr -d '\r' | sed '/^$/d'

if ((restore_rc != 0)); then
  die "Restore failed on '$server_name'. Database '$db_name' was not changed by a successful restore (see message above)."
fi

echo
echo "✔ Database [$db_name] restored on $server_name."
echo "  Snapshot: $bak_full_path"
