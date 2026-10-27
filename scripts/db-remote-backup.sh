#!/usr/bin/env bash
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

# Prints "Size / Uncompressed / Ratio / Duration" lines from "<bytes>|<bytes>|<ms>" on stdin.
print_backup_stats() {
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

convert_mode=0
script_args=()
for arg in "$@"; do
  if [[ "$arg" == "--convert" ]]; then
    convert_mode=1
  else
    script_args+=("$arg")
  fi
done
set -- "${script_args[@]+"${script_args[@]}"}"

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

# --convert only: a BACPAC exported from the source is imported into a throwaway
# local SQL Server container of the chosen older version, which writes the .bak.
sql_major_year() {
  case "$1" in
    17) echo 2025 ;;
    16) echo 2022 ;;
    15) echo 2019 ;;
    14) echo 2017 ;;
    *) return 1 ;;
  esac
}

ensure_docker_running() {
  require_cmd docker
  docker info >/dev/null 2>&1 && return 0

  echo "Docker is not running. Starting Docker Desktop..."
  case "$(uname -s)" in
    Darwin) open -g -a Docker || open -a Docker || true ;;
    Linux) systemctl --user start docker-desktop 2>/dev/null || true ;;
  esac

  local i
  for ((i = 1; i <= 60; i++)); do
    if docker info >/dev/null 2>&1; then
      echo "Docker is ready."
      return 0
    fi
    sleep 2
  done
  die "Docker did not become ready in time. Start Docker Desktop and retry."
}

convert_container=""
convert_work_dir=""

cleanup_convert() {
  if [[ -n "$convert_container" ]]; then
    docker rm -f "$convert_container" >/dev/null 2>&1 || true
    convert_container=""
  fi
  if [[ -n "$convert_work_dir" ]]; then
    rm -rf "$convert_work_dir"
    convert_work_dir=""
  fi
}

run_convert_snapshot() {
  local out_file="$1"
  local sa_pwd port local_server bacpac_file step_start i

  trap cleanup_convert EXIT
  convert_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/forge-rdbsn-convert.XXXXXX")"
  bacpac_file="$convert_work_dir/$selected_db.bacpac"

  echo
  echo "▶ Exporting BACPAC from '$server_name'..."
  echo "  Writes to the source during export are not captured consistently."
  step_start=$SECONDS
  "$SQLPACKAGE_BIN" /Action:Export \
    /SourceServerName:"$connect_server" \
    /SourceDatabaseName:"$selected_db" \
    /SourceUser:"$server_user" \
    /SourcePassword:"$server_pwd" \
    /SourceTrustServerCertificate:True \
    /TargetFile:"$bacpac_file" ||
    die "BACPAC export failed. Orphaned users (SQL71564) or unsupported objects are reported above."
  echo "  Export took $((SECONDS - step_start))s."

  echo
  echo "▶ Starting throwaway SQL Server $convert_year container ($convert_image)..."
  sa_pwd="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24)Aa1!"
  convert_container="forge-rdbsn-convert-$$"
  docker run -d --name "$convert_container" --platform linux/amd64 \
    -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$sa_pwd" \
    -p 127.0.0.1::1433 "$convert_image" >/dev/null ||
    die "Could not start container from $convert_image."

  port="$(docker port "$convert_container" 1433/tcp | head -n 1)"
  port="${port##*:}"
  [[ "$port" =~ ^[0-9]+$ ]] || die "Could not read the container's SQL port."
  local_server="tcp:127.0.0.1,$port"

  run_local_sqlcmd() {
    run_sqlcmd_raw -S "$local_server" -U sa -P "$sa_pwd" -C -b "$@"
  }

  for ((i = 1; i <= 90; i++)); do
    run_local_sqlcmd -Q "SELECT 1" >/dev/null 2>&1 && break
    ((i < 90)) || die "SQL Server container did not become ready in time."
    sleep 2
  done

  echo
  echo "▶ Importing BACPAC into SQL Server $convert_year..."
  step_start=$SECONDS
  "$SQLPACKAGE_BIN" /Action:Import \
    /TargetServerName:"$local_server" \
    /TargetDatabaseName:"$selected_db" \
    /TargetUser:sa \
    /TargetPassword:"$sa_pwd" \
    /TargetTrustServerCertificate:True \
    /SourceFile:"$bacpac_file" ||
    die "BACPAC import into SQL Server $convert_year failed. Objects using newer-version features are reported above."
  echo "  Import took $((SECONDS - step_start))s."

  echo
  echo "▶ Writing SQL Server $convert_year backup..."
  run_local_sqlcmd -Q "BACKUP DATABASE $(tsql_ident "$selected_db") TO DISK = N'/var/opt/mssql/data/forge-convert.bak' WITH INIT, COPY_ONLY, COMPRESSION, STATS = 25;" ||
    die "Backup inside the conversion container failed."
  docker cp "$convert_container:/var/opt/mssql/data/forge-convert.bak" "$out_file" >/dev/null ||
    die "Could not copy the backup out of the conversion container."

  cleanup_convert
  trap - EXIT

  echo
  echo "✔ SQL Server $convert_year backup created:"
  echo "  $out_file"
  printf '  Size           : %s\n' "$(du -h "$out_file" | cut -f1)"
  echo "  Users from the source keep their names; map them to logins after restore if needed."

  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo
    read -r -p "Upload it to a remote SQL backup path now (rup)? [y/N]: " upload_answer
    if [[ "${upload_answer,,}" == "y" || "${upload_answer,,}" == "yes" ]]; then
      "$SCRIPT_DIR/db-remote-upload.sh" "$out_file"
    fi
  fi
}

if ((convert_mode)); then
  source_major_raw="$(run_sqlcmd_capture "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS int);")" ||
    die "Failed to read the SQL Server version of '$server_name'."
  source_major="$(printf '%s' "$source_major_raw" | tr -d '\r' | sed '/^$/d' | head -n 1)"
  source_year="$(sql_major_year "$source_major")" ||
    die "Unsupported SQL Server major version '$source_major' on '$server_name'."

  version_rows="$(printf '%s\tSQL Server %s (native backup, same as source)\n' "$source_year" "$source_year")"
  for year in 2022 2019 2017; do
    ((year < source_year)) || continue
    version_rows+=$'\n'"$(printf '%s\tSQL Server %s (convert through BACPAC, local .bak)' "$year" "$year")"
  done

  convert_year="$(
    printf '%s\n' "$version_rows" |
      fzf --prompt='Snapshot version > ' --delimiter=$'\t' --with-nth=2 --height=30% --border |
      cut -f1
  )" || die "No snapshot version selected."
  [[ -n "$convert_year" ]] || die "No snapshot version selected."

  if [[ "$convert_year" == "$source_year" ]]; then
    convert_mode=0
  else
    SQLPACKAGE_BIN="${FORGE_SQLPACKAGE_BIN:-$(command -v sqlpackage || printf '%s' "$HOME/.dotnet/tools/sqlpackage")}"
    [[ -x "$SQLPACKAGE_BIN" ]] ||
      die "SqlPackage not found. Install it with: dotnet tool install -g microsoft.sqlpackage"

    ensure_docker_running
    if declare -F forge_sql_resolve_image >/dev/null; then
      convert_image="$(forge_sql_resolve_image "$convert_year")"
    else
      convert_image="mcr.microsoft.com/mssql/server:${convert_year}-latest"
    fi
    docker image inspect "$convert_image" >/dev/null 2>&1 ||
      die "SQL Server $convert_year image '$convert_image' not found locally. Run: docker pull $convert_image"
  fi
fi

name_suffix="${1:-}"
default_backup_name="${selected_db}_$(date +%Y%m%d)${name_suffix:+_$name_suffix}.bak"
if ((convert_mode)); then
  default_backup_name="${selected_db}_$(date +%Y%m%d)${name_suffix:+_$name_suffix}_sql${convert_year}.bak"
fi

echo "Target      : $server_name ($connect_server)"
if [[ -n "$expected_instance" ]]; then
  echo "Instance    : $expected_instance"
fi
echo "Database    : $selected_db"
if ((convert_mode)); then
  echo "Source      : SQL Server $source_year"
  echo "Convert to  : SQL Server $convert_year ($convert_image)"
  echo "Output dir  : $PWD"
else
  echo "Backup path : $backup_dir"
fi
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

if ((convert_mode)); then
  [[ "$backup_name" != */* ]] || die "Backup file name cannot contain '/'."
  convert_out_file="$PWD/$backup_name"
  if [[ -e "$convert_out_file" ]]; then
    read -r -p "$convert_out_file already exists. Overwrite? [y/N]: " overwrite_answer
    [[ "${overwrite_answer,,}" == "y" || "${overwrite_answer,,}" == "yes" ]] || die "Aborted; existing file kept."
  fi
  run_convert_snapshot "$convert_out_file"
  exit 0
fi

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

backup_stats="$(
  run_sqlcmd_raw \
    -S "$connect_server" \
    -U "$server_user" \
    -P "$server_pwd" \
    -C \
    -h -1 \
    -W \
    -s '|' \
    -Q "SET NOCOUNT ON; SELECT TOP 1 CAST(bs.backup_size AS bigint), CAST(ISNULL(bs.compressed_backup_size, bs.backup_size) AS bigint), DATEDIFF(MILLISECOND, bs.backup_start_date, bs.backup_finish_date) FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id WHERE mf.physical_device_name = N'$backup_full_path_sql' AND bs.type = 'D' ORDER BY bs.backup_set_id DESC;" \
    2>/dev/null | tr -d '\r' | sed '/^$/d' | head -n 1
)" || backup_stats=""

echo
echo "✔ Backup created:"
echo "  $backup_full_path"
printf '%s\n' "$backup_stats" | print_backup_stats
