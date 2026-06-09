#!/opt/homebrew/bin/bash
# vps1-sql-tunnel.sh — open/close the SSH tunnel to the private vps1 SQL Server.
#
# The MSSQL container (tnisoft-mssql) binds to 127.0.0.1:1433 on vps1 and is NOT
# public. To connect a local client (VS Code mssql extension, Azure Data Studio,
# sqlcmd) reach it at localhost:14333 by forwarding the port over SSH.
#
# In VS Code → SQL Server (mssql): Server = localhost,14333 · User = sa ·
# Trust server certificate = Yes.
#
# Usage:
#   vps1-sql-tunnel.sh up       # open the tunnel (idempotent)
#   vps1-sql-tunnel.sh down     # close the tunnel
#   vps1-sql-tunnel.sh status   # show whether it is up
#
# Aliases: v1-sql-tunnel-up (= up), v1-sql-tunnel-down (= down).
set -euo pipefail

#######################################
# Static config
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
SQL_LOCAL_PORT="${SQL_LOCAL_PORT:-14333}"
SQL_REMOTE="${SQL_REMOTE:-127.0.0.1:1433}"
FORWARD_SPEC="${SQL_LOCAL_PORT}:${SQL_REMOTE}"

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

listener_pids() {
  pgrep -f "ssh .*-L ?${FORWARD_SPEC}" 2>/dev/null || true
}

is_up() {
  lsof -nP -iTCP:"${SQL_LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_up; then
    log "SQL tunnel already up — localhost:${SQL_LOCAL_PORT} → ${VPS1_SSH_HOST}:${SQL_REMOTE}"
  else
    log "Opening SQL tunnel localhost:${SQL_LOCAL_PORT} → ${VPS1_SSH_HOST}:${SQL_REMOTE} ..."
    ssh -f -N -L "${FORWARD_SPEC}" "${VPS1_SSH_HOST}" \
      || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
    sleep 1
  fi
  if is_up; then
    echo "✔ SQL reachable at localhost:${SQL_LOCAL_PORT} (VS Code: Server = localhost,${SQL_LOCAL_PORT})"
    local pids; pids="$(listener_pids)"
    [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: v1-sql-tunnel-down"
  else
    die "Tunnel did not come up on localhost:${SQL_LOCAL_PORT}."
  fi
}

tunnel_down() {
  local pids; pids="$(listener_pids)"
  if [[ -z "${pids}" ]]; then
    log "No vps1 SQL tunnel found (nothing to close)."
    return 0
  fi
  log "Closing SQL tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  if is_up; then
    die "Port ${SQL_LOCAL_PORT} still in use after closing — check 'lsof -iTCP:${SQL_LOCAL_PORT}'."
  fi
  echo "✔ SQL tunnel closed."
}

tunnel_status() {
  if is_up; then
    local pids; pids="$(listener_pids)"
    echo "● UP — localhost:${SQL_LOCAL_PORT} → ${VPS1_SSH_HOST}:${SQL_REMOTE}${pids:+  (ssh pid: ${pids//$'\n'/ })}"
  else
    echo "○ DOWN — no listener on localhost:${SQL_LOCAL_PORT}. Open with: v1-sql-tunnel-up"
  fi
}

#######################################
# Main
#######################################
action="${1:-status}"
case "${action}" in
  up|--up)       tunnel_up ;;
  down|--down)   tunnel_down ;;
  status|--status) tunnel_status ;;
  -h|--help|help)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "Unknown action '${action}'. Use: up | down | status"
    ;;
esac
