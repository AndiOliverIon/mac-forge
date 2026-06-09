#!/opt/homebrew/bin/bash
# vps1.sh — shared config/helpers for the vps1 SQL snapshot workflow.
#
# Sourced by scripts/vps1/vps1-db-*.sh. Operates against the dev SQL Server
# (tnisoft-mssql container) on the vps1 station.
#
# Design:
#   - SQL operations run as LOCAL sqlcmd over TCP to the vps1 public endpoint
#     (server/user/password taken from config-local/local-store.json).
#   - File operations (list/download) run over ssh/rsync to the vps1 host.
#   - Single dedicated snapshots folder on vps1:
#       host:      /srv/tnisoft/mssql/snapshots
#       container: /var/opt/mssql/snapshots

#######################################
# Static config (vps1 station)
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
VPS1_SQL_CONTAINER="${VPS1_SQL_CONTAINER:-tnisoft-mssql}"
VPS1_SNAPSHOTS_HOST_DIR="${VPS1_SNAPSHOTS_HOST_DIR:-/srv/tnisoft/mssql/snapshots}"
VPS1_SNAPSHOTS_CONTAINER_DIR="${VPS1_SNAPSHOTS_CONTAINER_DIR:-/var/opt/mssql/snapshots}"
VPS1_SQL_DATA_DIR="${VPS1_SQL_DATA_DIR:-/var/opt/mssql/data}"
VPS1_CONNECTION_NAME="${VPS1_CONNECTION_NAME:-VPS1}"
VPS1_SQLCMD_GODEBUG="${VPS1_SQLCMD_GODEBUG:-x509negativeserial=1}"
VPS1_SSH_CONNECT_TIMEOUT="${VPS1_SSH_CONNECT_TIMEOUT:-15}"

#######################################
# Resolve repo root / local-store
#######################################
VPS1_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPS1_REPO_ROOT="$(cd "$VPS1_SCRIPT_DIR/../.." && pwd)"
VPS1_LOCAL_STORE_FILE="${VPS1_LOCAL_STORE_FILE:-$VPS1_REPO_ROOT/config-local/local-store.json}"

#######################################
# Helpers
#######################################
vps1_die() { echo "✖ $*" >&2; exit 1; }
vps1_require_cmd() { command -v "$1" >/dev/null 2>&1 || vps1_die "Required command '$1' not found."; }
vps1_log_step() { echo "→ $*"; }

# Load connection (host/port/user/password) from local-store.json by display name.
vps1_load_connection() {
  vps1_require_cmd python3
  [[ -f "$VPS1_LOCAL_STORE_FILE" ]] || vps1_die "Missing local store file: $VPS1_LOCAL_STORE_FILE"

  local parsed
  parsed="$(
    python3 - "$VPS1_LOCAL_STORE_FILE" "$VPS1_CONNECTION_NAME" <<'PY'
import json, sys
f, name = sys.argv[1], sys.argv[2]
j = json.load(open(f, encoding="utf-8"))
for c in j.get("connections", []):
    if c.get("display") == name:
        server = (c.get("server") or "").strip()
        host, _, port = server.partition(",")
        print("HOST\t" + host.strip())
        print("PORT\t" + port.strip())
        print("USER\t" + (c.get("user") or ""))
        print("PASS\t" + (c.get("password") or ""))
        break
else:
    sys.exit(3)
PY
  )" || vps1_die "Connection '$VPS1_CONNECTION_NAME' not found in $VPS1_LOCAL_STORE_FILE"

  local key value
  while IFS=$'\t' read -r key value; do
    case "$key" in
      HOST) VPS1_SQL_HOST="$value" ;;
      PORT) VPS1_SQL_PORT="$value" ;;
      USER) VPS1_SQL_USER="$value" ;;
      PASS) VPS1_SQL_PASSWORD="$value" ;;
    esac
  done <<< "$parsed"

  [[ -n "${VPS1_SQL_HOST:-}" && -n "${VPS1_SQL_USER:-}" && -n "${VPS1_SQL_PASSWORD:-}" ]] \
    || vps1_die "Connection '$VPS1_CONNECTION_NAME' is missing host/user/password."

  if [[ -n "${VPS1_SQL_PORT:-}" ]]; then
    VPS1_SQL_SERVER="tcp:${VPS1_SQL_HOST},${VPS1_SQL_PORT}"
  else
    VPS1_SQL_SERVER="tcp:${VPS1_SQL_HOST}"
  fi
}

# Run local sqlcmd against vps1 over TCP. Extra args are appended.
vps1_sqlcmd() {
  if [[ -n "$VPS1_SQLCMD_GODEBUG" ]]; then
    GODEBUG="$VPS1_SQLCMD_GODEBUG" sqlcmd -S "$VPS1_SQL_SERVER" -U "$VPS1_SQL_USER" -P "$VPS1_SQL_PASSWORD" -C "$@"
  else
    sqlcmd -S "$VPS1_SQL_SERVER" -U "$VPS1_SQL_USER" -P "$VPS1_SQL_PASSWORD" -C "$@"
  fi
}

vps1_wait_for_sql_ready() {
  local max_tries="${1:-30}" i
  vps1_log_step "Waiting for vps1 SQL Server ($VPS1_SQL_SERVER) to be ready..."
  for ((i = 1; i <= max_tries; i++)); do
    if vps1_sqlcmd -b -Q "SELECT 1" >/dev/null 2>&1; then
      vps1_log_step "vps1 SQL Server is ready (attempt $i)."
      return 0
    fi
    sleep 2
  done
  vps1_die "vps1 SQL Server did not become ready after $((max_tries * 2)) seconds."
}

# ssh helper for file operations on the vps1 host.
vps1_ssh() { ssh -o ConnectTimeout="$VPS1_SSH_CONNECT_TIMEOUT" "$VPS1_SSH_HOST" "$@"; }

# List *.bak basenames in the host snapshots dir (newest first).
vps1_list_snapshots() {
  vps1_ssh "ls -1t '$VPS1_SNAPSHOTS_HOST_DIR'/*.bak 2>/dev/null | xargs -r -n1 basename"
}

# Make a snapshot file world-readable (SQL writes as the container's mssql uid,
# so the ssh user needs read access to rsync it back).
vps1_chmod_snapshot() {
  local name="$1"
  vps1_ssh "docker exec -u 0 '$VPS1_SQL_CONTAINER' chmod 644 '$VPS1_SNAPSHOTS_CONTAINER_DIR/$name' 2>/dev/null || true"
}
