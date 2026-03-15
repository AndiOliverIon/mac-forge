#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/forge.sh"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_GREEN=$'\033[1;32m'
  C_RED=$'\033[1;31m'
else
  C_RESET=''
  C_BLUE=''
  C_CYAN=''
  C_GREEN=''
  C_RED=''
fi

print_line() {
  local color="$1"
  local icon="$2"
  shift 2
  printf '%s[%s]%s %s\n' "$color" "$icon" "$C_RESET" "$*"
}

section() {
  printf '\n%s%s%s\n' "$C_BLUE" "$1" "$C_RESET"
}

log_step() {
  print_line "$C_CYAN" '>' "$*"
}

log_info() {
  print_line "$C_BLUE" 'i' "$*"
}

log_success() {
  print_line "$C_GREEN" '+' "$*"
}

die() {
  print_line "$C_RED" 'x' "$*" >&2
  exit 1
}

detect_target_framework() {
  local csproj="$1"
  local tfm tfms

  tfm="$(sed -n 's/.*<TargetFramework>\(.*\)<\/TargetFramework>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfm" ]]; then
    printf '%s\n' "$tfm"
    return 0
  fi

  tfms="$(sed -n 's/.*<TargetFrameworks>\(.*\)<\/TargetFrameworks>.*/\1/p' "$csproj" | head -n1)"
  if [[ -n "$tfms" ]]; then
    printf '%s\n' "${tfms%%;*}"
    return 0
  fi

  return 1
}

wait_for_sql_ready() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"
  local max_tries=30
  local i

  log_step "Waiting for SQL Server in container '$container_name'..."

  for ((i = 1; i <= max_tries; i++)); do
    if ! docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
      die "SQL Server container '$container_name' is not running."
    fi

    if docker exec "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C -d master \
      -Q "SELECT 1" >/dev/null 2>&1; then
      log_success "SQL Server is ready."
      return 0
    fi

    sleep 2
  done

  die "SQL Server did not become ready."
}

choose_database() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"

  mapfile -t db_list < <(
    docker exec "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C \
      -h -1 -W \
      -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;" |
      sed '/^$/d'
  )

  ((${#db_list[@]} > 0)) || die "No user databases found."

  printf '%s\n' "${db_list[@]}" | fzf --prompt='Select database to migrate > ' --height=40%
}

choose_migrations_path() {
  local paths_json="$1"
  local selection

  mapfile -t paths < <(
    python3 - "$paths_json" <<'PY'
import json
import sys

for item in json.loads(sys.argv[1]):
    if isinstance(item, str) and item.strip():
        print(item.strip())
PY
  )

  ((${#paths[@]} > 0)) || die "No Ardis migration paths configured."

  if ((${#paths[@]} == 1)); then
    printf '%s\n' "${paths[0]}"
    return 0
  fi

  selection="$(
    printf '%s\n' "${paths[@]}" | fzf \
      --prompt='Select Ardis clone > ' \
      --height=40% \
      --header='Esc uses the first configured path'
  )" || true

  if [[ -n "$selection" ]]; then
    printf '%s\n' "$selection"
    return 0
  fi

  printf '%s\n' "${paths[0]}"
}

main() {
  forge_require_cmd docker
  forge_require_cmd fzf
  forge_require_cmd dotnet
  forge_assert_sensitive_config

  local migrations_path migrations_paths_json migrations_library csproj tfm bin_dir
  local container_name host_port sql_user sqlcmd_path sa_password db_name conn_str

  migrations_paths_json="$(forge_get_json_optional ardis.migrations_paths)"
  migrations_library="$(forge_get_optional ardis.migrations_library)"
  [[ -n "$migrations_paths_json" ]] || migrations_paths_json='["'"$HOME"'/work/ardis-perform/Ardis.Migrations.Console"]'
  [[ -n "$migrations_library" ]] || migrations_library="Ardis.Migrations.Console.dll"

  container_name="$(forge_get docker.container_name)"
  host_port="$(forge_get docker.host_port)"
  sql_user="$(forge_get docker.sql_user)"
  sqlcmd_path="$(forge_get docker.sqlcmd_path)"
  sa_password="$(forge_get sql.sa_password)"

  [[ "$sql_user" == "sa" ]] || die "This migration flow currently supports sql_user=sa only."

  migrations_path="$(choose_migrations_path "$migrations_paths_json")"

  csproj="${migrations_path}/Ardis.Migrations.Console.csproj"
  [[ -f "$csproj" ]] || die "csproj not found at $csproj"

  docker ps --format '{{.Names}}' | grep -qx "$container_name" || die "SQL container '$container_name' is not running."
  wait_for_sql_ready "$container_name" "$sqlcmd_path" "$sa_password"

  section "Migration Plan"
  log_info "Project     $csproj"
  log_info "Container   $container_name"
  log_info "SQL host    localhost:$host_port"

  log_step "Detecting target framework..."
  tfm="$(detect_target_framework "$csproj")" || die "Could not detect TargetFramework from $csproj"
  bin_dir="${migrations_path}/bin/Debug/${tfm}"
  log_info "Framework   $tfm"

  log_step "Building migrations project..."
  (
    cd "$migrations_path"
    dotnet build "$csproj" --configuration Debug
  )

  [[ -d "$bin_dir" ]] || die "Build output folder not found: $bin_dir"

  db_name="$(choose_database "$container_name" "$sqlcmd_path" "$sa_password")" || die "No database selected."
  [[ -n "$db_name" ]] || die "No database selected."
  log_info "Database    $db_name"

  conn_str="Server=localhost,${host_port};Database=${db_name};User ID=${sql_user};Password=${sa_password};TrustServerCertificate=True;Encrypt=False;"
  export MIGRATIONS_DatabaseConnectionString="$conn_str"

  section "Running"
  log_step "Launching migrations..."
  (
    cd "$bin_dir"
    dotnet "$migrations_library" --v --logs --demo
  )

  printf '\n'
  log_success "Ardis migrations completed."

  section "Migration Summary"
  log_success "Database    $db_name"
  log_success "Project     $migrations_path"
  log_success "Assembly    ${bin_dir}/${migrations_library}"
  log_success "SQL         localhost:$host_port"
  log_info "Connection  Server=localhost,${host_port};Database=${db_name};User ID=${sql_user};Password=***;TrustServerCertificate=True;Encrypt=False;"
}

main "$@"
