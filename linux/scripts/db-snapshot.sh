#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/forge.sh"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
else
  C_RESET=''
  C_BLUE=''
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
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

log_warn() {
  print_line "$C_YELLOW" '!' "$*"
}

die() {
  print_line "$C_RED" 'x' "$*" >&2
  exit 1
}

format_bytes() {
  local bytes="${1:-0}"
  awk -v bytes="$bytes" '
    BEGIN {
      split("B KB MB GB TB PB", units, " ")
      i = 1
      while (bytes >= 1000 && i < 6) {
        bytes /= 1000
        i++
      }
      printf "%.1f %s", bytes, units[i]
    }'
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

pick_database() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"

  mapfile -t db_list < <(
    docker exec "$container_name" \
      "$sqlcmd_path" \
      -S localhost -U sa -P "$sa_password" -C \
      -h -1 -W \
      -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') ORDER BY name;" |
      sed '/^$/d'
  )

  ((${#db_list[@]} > 0)) || die "No user databases found."

  printf '%s\n' "${db_list[@]}" | fzf --prompt='Select database to snapshot > ' --height=40%
}

db_size_bytes() {
  local container_name="$1"
  local sqlcmd_path="$2"
  local sa_password="$3"
  local db_name="$4"

  docker exec "$container_name" \
    "$sqlcmd_path" \
    -S localhost -U sa -P "$sa_password" -C \
    -h -1 -W \
    -Q "SET NOCOUNT ON; SELECT COALESCE(SUM(CAST(size AS bigint)) * 8 * 1024, 0) FROM sys.master_files WHERE database_id = DB_ID(N'$db_name');" |
    awk 'NF {print; exit}'
}

main() {
  forge_require_cmd docker
  forge_require_cmd fzf
  forge_require_cmd stat
  forge_assert_sensitive_config

  local container_name host_port sql_user sqlcmd_path
  local snapshots_container_path snapshots_host_path
  local sa_password db_name snapshot_suffix snapshot_name
  local snapshot_host_path snapshot_container_path
  local db_bytes snapshot_bytes

  container_name="$(forge_get docker.container_name)"
  host_port="$(forge_get docker.host_port)"
  sql_user="$(forge_get docker.sql_user)"
  sqlcmd_path="$(forge_get docker.sqlcmd_path)"
  snapshots_container_path="$(forge_get docker.container_snapshots_path)"
  snapshots_host_path="$(forge_get_path_from_root paths.restore_stage_path paths.sql_storage_root)"
  sa_password="$(forge_get sql.sa_password)"

  docker ps --format '{{.Names}}' | grep -qx "$container_name" || die "SQL container '$container_name' is not running."

  wait_for_sql_ready "$container_name" "$sqlcmd_path" "$sa_password"

  mkdir -p "$snapshots_host_path"
  [[ -d "$snapshots_host_path" && -w "$snapshots_host_path" ]] || die "Snapshots path not writable on host: $snapshots_host_path"

  section "Snapshot Plan"
  db_name="$(pick_database "$container_name" "$sqlcmd_path" "$sa_password")" || die "No database selected."
  [[ -n "$db_name" ]] || die "No database selected."
  log_info "Database    $db_name"

  if [[ $# -ge 1 ]]; then
    snapshot_suffix="$1"
  else
    read -r -p "Snapshot label [manual]: " snapshot_suffix
    snapshot_suffix="${snapshot_suffix:-manual}"
  fi

  snapshot_suffix="${snapshot_suffix// /-}"
  [[ -n "$snapshot_suffix" ]] || die "Snapshot label cannot be empty."

  snapshot_name="${db_name}_${snapshot_suffix}.bak"
  snapshot_host_path="${snapshots_host_path}/${snapshot_name}"
  snapshot_container_path="${snapshots_container_path}/${snapshot_name}"

  log_info "Snapshot    $snapshot_name"
  log_info "Target      $snapshot_host_path"

  db_bytes="$(db_size_bytes "$container_name" "$sqlcmd_path" "$sa_password" "$db_name")"
  db_bytes="${db_bytes:-0}"
  if [[ ! "$db_bytes" =~ ^[0-9]+$ ]]; then
    db_bytes=0
  fi

  log_step "Creating snapshot in SQL Server..."
  docker exec "$container_name" \
    "$sqlcmd_path" \
    -S localhost -U sa -P "$sa_password" -C \
    -b \
    -Q "BACKUP DATABASE [$db_name] TO DISK = N'$snapshot_container_path' WITH INIT, STATS = 10;"

  [[ -f "$snapshot_host_path" ]] || die "Backup reported success but snapshot not found on host: $snapshot_host_path"

  snapshot_bytes="$(stat -c '%s' "$snapshot_host_path" 2>/dev/null || printf '0')"
  if [[ ! "$snapshot_bytes" =~ ^[0-9]+$ ]]; then
    snapshot_bytes=0
  fi

  printf '\n'
  log_success "Snapshot completed."

  section "Snapshot Summary"
  log_success "Database    $db_name"
  log_success "Snapshot    $snapshot_name"
  log_success "Host path   $snapshot_host_path"
  log_success "Container   $snapshot_container_path"
  log_success "SQL server  localhost:$host_port"
  log_info "DB size     $(format_bytes "$db_bytes")"
  log_info "Bak size    $(format_bytes "$snapshot_bytes")"

  if [[ "$db_bytes" -gt 0 && "$snapshot_bytes" -gt 0 ]]; then
    log_info "Ratio       $(awk -v db="$db_bytes" -v bak="$snapshot_bytes" 'BEGIN { printf "%.1f%%", (bak / db) * 100 }') of DB size"
  else
    log_warn "Ratio       unavailable"
  fi
}

main "$@"
