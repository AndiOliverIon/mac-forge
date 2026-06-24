#!/opt/homebrew/bin/bash
# ardis-migrate-remote.sh (alias: ram)
#
# Mirrors scripts/ardis-migrate.sh ('am') and scripts/vps1/vps1-db-migrate.sh
# ('v1am'), but targets one of the configured remote SQL Server entries
# (config-local/local-store.json -> remote_sql, the same servers used by
# 'rdbsn' / 'rdbr'). The migrations console still builds and runs locally on
# this Mac; only its connection string points at the chosen remote server.
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

#######################################
# Required variables
#######################################
: "${ARDIS_MIGRATIONS_LIBRARY:?ARDIS_MIGRATIONS_LIBRARY must be set in forge.sh}"

#######################################
# Tooling checks
#######################################
require_cmd fzf
require_cmd jq
require_cmd sqlcmd
require_cmd python3
require_cmd dotnet
DOTNET="$(command -v dotnet)"

SQLCMD_BIN="${FORGE_SQLCMD_BIN:-$(command -v sqlcmd)}"
SQLCMD_GODEBUG="${FORGE_SQLCMD_GODEBUG:-x509negativeserial=1}"

LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$HOME/mac-forge/config-local}/local-store.json"
[[ -f "$LOCAL_STORE_FILE" ]] || die "Missing local store file: $LOCAL_STORE_FILE"

require_sdk_major() {
  local major="$1"
  dotnet --list-sdks 2>/dev/null | awk '{print $1}' | grep -Eq "^${major}\." \
    || { echo "Required .NET SDK ${major}.x not found." >&2; dotnet --list-sdks >&2 || true; exit 1; }
}
require_runtime_major() {
  local major="$1"
  dotnet --list-runtimes 2>/dev/null | awk '{print $1" "$2}' | grep -Eq "^Microsoft\.NETCore\.App ${major}\." \
    || { echo "Required .NET runtime Microsoft.NETCore.App ${major}.x not found." >&2; dotnet --list-runtimes >&2 || true; exit 1; }
}
require_sdk_major 9
require_runtime_major 8

#######################################
# Helpers
#######################################
is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

detect_target_framework() {
  local csproj="$1" tfm tfms
  tfm="$(sed -n 's/.*<TargetFramework>\(.*\)<\/TargetFramework>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfm" ]]; then printf '%s\n' "$tfm"; return 0; fi
  tfms="$(sed -n 's/.*<TargetFrameworks>\(.*\)<\/TargetFrameworks>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfms" ]]; then printf '%s\n' "${tfms%%;*}"; return 0; fi
  return 1
}

choose_migrations_path() {
  local selected
  if [[ -n "${FORGE_WORK_STATE_FILE:-}" && -f "${FORGE_WORK_STATE_FILE}" ]]; then
    selected="$(
      python3 - "$FORGE_WORK_STATE_FILE" <<'PY' | fzf --prompt='Select migrations path: ' --with-nth=1,2 --delimiter=$'\t' --height=20 --border
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
for entry in state.get("ardis-migration-paths", []):
    title = (entry.get("title") or "").strip()
    path = (entry.get("path") or "").strip()
    if path:
        print(f"{title}\t{path}")
PY
    )" || { echo "No migrations path selected. Aborting." >&2; return 1; }
    if [[ -n "${selected:-}" ]]; then printf '%s\n' "${selected#*$'\t'}"; return 0; fi
  fi
  if [[ -n "${ARDIS_MIGRATIONS_PATH:-}" ]]; then printf '%s\n' "$ARDIS_MIGRATIONS_PATH"; return 0; fi
  echo "No migrations paths configured. Add 'ardis-migration-paths' to ${FORGE_WORK_STATE_FILE:-configs/work-state.json}." >&2
  return 1
}

run_sqlcmd_raw() {
  if [[ -n "$SQLCMD_GODEBUG" ]]; then
    GODEBUG="$SQLCMD_GODEBUG" "$SQLCMD_BIN" "$@"
  else
    "$SQLCMD_BIN" "$@"
  fi
}

run_q_rows() {
  local query="$1" out rc
  set +e
  out="$(
    run_sqlcmd_raw \
      -S "$connect_server" -U "$server_user" -P "$server_pwd" \
      -C -b -h -1 -W -w 65535 \
      -Q "$query" 2>&1
  )"
  rc=$?
  set -e
  if ((rc != 0)); then
    die "SQL query failed on '$server_name' ($connect_server):"$'\n'"$(printf '%s' "$out" | tr -d '\r' | sed '/^$/d' | tail -n 12)"
  fi
  printf '%s' "$out" | tr -d '\r' | sed '/^$/d'
}

#######################################
# Select remote SQL target (same source as rdbsn / rdbr)
#######################################
select_remote_target() {
  local selection_tsv chosen_line
  selection_tsv="$(
    jq -r '
      (.remote_sql // [])
      | to_entries[]?
      | select(
          .value.name != null and
          .value.user != null and
          .value.pwd != null and
          ((.value.serverurl != null) or (.value.host != null))
        )
      | [
          .value.name,
          (.value.serverurl // ""),
          (.value.host // ""),
          (.value.port // ""),
          (.value.instance // ""),
          (.value.instance_strict // false),
          .value.user,
          .value.pwd
        ]
      | @tsv
    ' "$LOCAL_STORE_FILE"
  )"

  [[ -n "${selection_tsv//$'\n'/}" ]] || die "No valid entries under remote_sql in $LOCAL_STORE_FILE"

  chosen_line="$(
    printf '%s\n' "$selection_tsv" \
      | fzf --prompt='Remote SQL target > ' --delimiter=$'\t' --with-nth=1,2,3,4,5 --height=65%
  )" || die "No remote SQL target selected."

  server_name="$(printf '%s' "$chosen_line" | cut -f1)"
  server_url="$(printf '%s' "$chosen_line" | cut -f2)"
  server_host="$(printf '%s' "$chosen_line" | cut -f3)"
  server_port="$(printf '%s' "$chosen_line" | cut -f4)"
  server_instance="$(printf '%s' "$chosen_line" | cut -f5)"
  instance_strict_raw="$(printf '%s' "$chosen_line" | cut -f6)"
  server_user="$(printf '%s' "$chosen_line" | cut -f7)"
  server_pwd="$(printf '%s' "$chosen_line" | cut -f8)"

  [[ -n "$server_user" && -n "$server_pwd" ]] || die "Selected remote_sql entry is missing user/pwd."

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
    [[ -n "$server_instance" ]] && expected_instance="$server_instance"
  else
    connect_server="$server_url"
    if [[ "$connect_server" == *,*\\* || "$connect_server" == *\\*,* ]]; then
      die "remote_sql entry '$server_name' has invalid serverurl '$connect_server'. Use structured fields host/port/instance instead."
    fi
  fi

  [[ -n "$connect_server" ]] || die "Selected remote_sql entry does not define a usable server address."
}

verify_instance() {
  [[ -n "$expected_instance" ]] || return 0
  local instance_actual
  instance_actual="$(run_q_rows "SET NOCOUNT ON; SELECT COALESCE(CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128)), N'MSSQLSERVER');" | head -n 1)"
  [[ -n "$instance_actual" ]] || die "Connected, but could not read SQL instance name."
  if [[ "${instance_actual,,}" != "${expected_instance,,}" ]]; then
    if is_truthy "$instance_strict_raw"; then
      die "Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'."
    fi
    echo "⚠ Connected instance mismatch for '$server_name': expected '$expected_instance', got '$instance_actual'." >&2
    echo "  Continuing because instance_strict is false." >&2
  fi
}

choose_database() {
  local dbs selected
  echo "Querying databases from '$server_name' ($connect_server)..." >&2
  dbs="$(run_q_rows "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;")"
  [[ -n "${dbs// /}" ]] || die "No user databases found on '$server_name'."
  selected="$(printf '%s\n' "$dbs" | fzf --prompt="Select database on $server_name to migrate: " --height=20 --border)"
  [[ -n "${selected:-}" ]] || die "No database selected."
  printf '%s\n' "$selected"
}

#######################################
# Main
#######################################
main() {
  local migrations_path csproj tfm bin_dir db conn_str

  select_remote_target
  verify_instance

  migrations_path="$(choose_migrations_path)" || exit 1

  csproj="$migrations_path/Ardis.Migrations.Console.csproj"
  [[ -f "$csproj" ]] || die "csproj not found at $csproj"

  echo "Selected migrations path: $migrations_path"
  echo "Using dotnet: $DOTNET"
  echo "Detecting TargetFramework from $csproj..."
  tfm="$(detect_target_framework "$csproj")" || die "Could not detect TargetFramework from $csproj"
  echo "TargetFramework: $tfm"

  echo "Building migrations project..."
  ( cd "$migrations_path" && dotnet build "$csproj" --configuration Debug )

  bin_dir="$migrations_path/bin/Debug/$tfm"
  [[ -d "$bin_dir" ]] || die "Build output folder not found: $bin_dir"
  echo "Build output: $bin_dir"

  db="$(choose_database)" || exit 1
  echo "Selected database: $db"
  echo
  echo "⚠ TARGET IS REMOTE: '$server_name' ($connect_server). Migrations will run against the live server."

  conn_str="Server=${connect_server};Database=${db};User ID=${server_user};Password=${server_pwd};TrustServerCertificate=True;Encrypt=False;"
  export MIGRATIONS_DatabaseConnectionString="$conn_str"
  export MIGRATIONS_DatasourceValidation="false"

  echo "Using MIGRATIONS_DatabaseConnectionString (password hidden):"
  echo "  Server=${connect_server};Database=${db};User ID=${server_user};Password=********;TrustServerCertificate=True;Encrypt=False;"
  echo "Using MIGRATIONS_DatasourceValidation=false"
  echo

  echo "Running migrations from: $bin_dir/$ARDIS_MIGRATIONS_LIBRARY"
  ( cd "$bin_dir" && dotnet "$ARDIS_MIGRATIONS_LIBRARY" --v --logs --demo )
}

main "$@"
