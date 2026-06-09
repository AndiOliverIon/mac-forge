#!/opt/homebrew/bin/bash
# vps1-db-migrate.sh — run Ardis migrations against a database on vps1.
#
# Mirrors scripts/ardis-migrate.sh ('am'), but targets the vps1 SQL Server
# (connection from config-local/local-store.json -> connections[VPS1]) instead
# of the local docker container. The migrations console still builds and runs
# locally on this Mac; only its connection string points at vps1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

# forge.sh provides ARDIS_MIGRATIONS_LIBRARY / FORGE_WORK_STATE_FILE / ARDIS_MIGRATIONS_PATH.
if [[ -f "$VPS1_REPO_ROOT/scripts/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VPS1_REPO_ROOT/scripts/forge.sh"
fi

#######################################
# Required variables
#######################################
: "${ARDIS_MIGRATIONS_LIBRARY:?ARDIS_MIGRATIONS_LIBRARY must be set in forge.sh}"

#######################################
# Tooling checks
#######################################
vps1_require_cmd fzf
vps1_require_cmd sqlcmd
vps1_require_cmd python3
command -v dotnet >/dev/null 2>&1 || vps1_die "Required command 'dotnet' not found in PATH."
DOTNET="$(command -v dotnet)"

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
# Helper: detect TargetFramework from .csproj
#######################################
detect_target_framework() {
  local csproj="$1" tfm tfms
  tfm="$(sed -n 's/.*<TargetFramework>\(.*\)<\/TargetFramework>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfm" ]]; then printf '%s\n' "$tfm"; return 0; fi
  tfms="$(sed -n 's/.*<TargetFrameworks>\(.*\)<\/TargetFrameworks>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfms" ]]; then printf '%s\n' "${tfms%%;*}"; return 0; fi
  return 1
}

#######################################
# Helper: choose migrations path from state json
#######################################
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

#######################################
# Helper: choose DB from vps1
#######################################
choose_database() {
  local dbs selected
  echo "Querying databases from vps1 ($VPS1_SQL_SERVER)..." >&2
  dbs="$(vps1_sqlcmd -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;" 2>/dev/null | tr -d '\r' | sed '/^$/d')"
  if [[ -z "${dbs// /}" ]]; then echo "No user databases found on vps1 (or query failed)." >&2; return 1; fi
  selected="$(printf '%s\n' "$dbs" | fzf --prompt='Select vps1 database to migrate: ' --height=20 --border)"
  [[ -n "${selected:-}" ]] || { echo "No database selected. Aborting." >&2; return 1; }
  printf '%s\n' "$selected"
}

#######################################
# Main
#######################################
main() {
  local migrations_path csproj tfm bin_dir db conn_str

  vps1_load_connection
  vps1_wait_for_sql_ready

  migrations_path="$(choose_migrations_path)" || exit 1

  csproj="$migrations_path/Ardis.Migrations.Console.csproj"
  [[ -f "$csproj" ]] || vps1_die "csproj not found at $csproj"

  echo "Selected migrations path: $migrations_path"
  echo "Using dotnet: $DOTNET"
  echo "Detecting TargetFramework from $csproj..."
  tfm="$(detect_target_framework "$csproj")" || vps1_die "Could not detect TargetFramework from $csproj"
  echo "TargetFramework: $tfm"

  echo "Building migrations project..."
  ( cd "$migrations_path" && dotnet build "$csproj" --configuration Debug )

  bin_dir="$migrations_path/bin/Debug/$tfm"
  [[ -d "$bin_dir" ]] || vps1_die "Build output folder not found: $bin_dir"
  echo "Build output: $bin_dir"

  db="$(choose_database)" || exit 1
  echo "Selected database: $db"
  echo
  echo "⚠ TARGET IS vps1 ($VPS1_SQL_HOST). Migrations will run against the live server."

  conn_str="Server=${VPS1_SQL_HOST}${VPS1_SQL_PORT:+,${VPS1_SQL_PORT}};Database=${db};User ID=${VPS1_SQL_USER};Password=${VPS1_SQL_PASSWORD};TrustServerCertificate=True;Encrypt=False;"
  export MIGRATIONS_DatabaseConnectionString="$conn_str"
  export MIGRATIONS_DatasourceValidation="false"

  echo "Using MIGRATIONS_DatabaseConnectionString (password hidden):"
  echo "  Server=${VPS1_SQL_HOST}${VPS1_SQL_PORT:+,${VPS1_SQL_PORT}};Database=${db};User ID=${VPS1_SQL_USER};Password=********;TrustServerCertificate=True;Encrypt=False;"
  echo "Using MIGRATIONS_DatasourceValidation=false"
  echo

  echo "Running migrations from: $bin_dir/$ARDIS_MIGRATIONS_LIBRARY"
  ( cd "$bin_dir" && dotnet "$ARDIS_MIGRATIONS_LIBRARY" --v --logs --demo )
}

main "$@"
