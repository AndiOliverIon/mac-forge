#!/opt/homebrew/bin/bash
# vps1-tally-tunnel.sh — open/close the SSH tunnel to the private Tally dev API.
#
# The dev endpoint (tally-api@dev) binds to 127.0.0.1:5181 on vps1 and is NOT
# public (no Caddy vhost, not in DNS). To let the local macOS app (Debug build)
# reach it at http://localhost:5181, forward the port over SSH. Production needs
# no tunnel (it is public at https://api.tally.tnisoft.ro).
#
# Usage:
#   vps1-tally-tunnel.sh up       # open the tunnel (idempotent)
#   vps1-tally-tunnel.sh down     # close the tunnel
#   vps1-tally-tunnel.sh status   # show whether it is up + dev health
#
# Aliases: v1-tally-tunnel-up (= up), v1-tally-tunnel-down (= down).
set -euo pipefail

#######################################
# Static config
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
TALLY_DEV_PORT="${TALLY_DEV_PORT:-5181}"
TALLY_DEV_REMOTE="${TALLY_DEV_REMOTE:-127.0.0.1:${TALLY_DEV_PORT}}"
TALLY_DEV_HEALTH_URL="http://localhost:${TALLY_DEV_PORT}/api/v1/health"
FORWARD_SPEC="${TALLY_DEV_PORT}:${TALLY_DEV_REMOTE}"

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

listener_pids() {
  # PIDs of ssh processes holding this exact local-forward.
  pgrep -f "ssh .*-L ?${FORWARD_SPEC}" 2>/dev/null || true
}

is_up() {
  lsof -nP -iTCP:"${TALLY_DEV_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

dev_health() {
  curl -sS -m 5 "${TALLY_DEV_HEALTH_URL}" 2>/dev/null || true
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_up; then
    log "Tunnel already up — localhost:${TALLY_DEV_PORT} → ${VPS1_SSH_HOST}:${TALLY_DEV_REMOTE}"
  else
    log "Opening tunnel localhost:${TALLY_DEV_PORT} → ${VPS1_SSH_HOST}:${TALLY_DEV_REMOTE} ..."
    ssh -f -N -L "${FORWARD_SPEC}" "${VPS1_SSH_HOST}" \
      || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
    sleep 1
  fi

  local health
  health="$(dev_health)"
  if [[ "${health}" == *'"status":"ok"'* ]]; then
    echo "✔ Dev API reachable at ${TALLY_DEV_HEALTH_URL}"
  else
    echo "⚠ Tunnel is up but dev /health did not report ok yet."
    [[ -n "${health}" ]] && echo "  ${health}"
  fi
  local pids; pids="$(listener_pids)"
  [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: v1-tally-tunnel-down"
}

tunnel_down() {
  local pids; pids="$(listener_pids)"
  if [[ -z "${pids}" ]]; then
    log "No Tally dev tunnel found (nothing to close)."
    return 0
  fi
  log "Closing tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  if is_up; then
    die "Port ${TALLY_DEV_PORT} still in use after closing — check 'lsof -iTCP:${TALLY_DEV_PORT}'."
  fi
  echo "✔ Tunnel closed."
}

tunnel_status() {
  if is_up; then
    local pids; pids="$(listener_pids)"
    echo "● UP — localhost:${TALLY_DEV_PORT} → ${VPS1_SSH_HOST}:${TALLY_DEV_REMOTE}${pids:+  (ssh pid: ${pids//$'\n'/ })}"
    local health; health="$(dev_health)"
    [[ -n "${health}" ]] && echo "  health: ${health}"
  else
    echo "○ DOWN — no listener on localhost:${TALLY_DEV_PORT}. Open with: v1-tally-tunnel-up"
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
