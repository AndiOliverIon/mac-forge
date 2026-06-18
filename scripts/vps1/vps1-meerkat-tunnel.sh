#!/opt/homebrew/bin/bash
# vps1-meerkat-tunnel.sh — open/close the SSH tunnel to the private Meerkat dev API.
#
# The dev endpoint (meerkat-backend@dev) binds to 127.0.0.1:5281 on vps1 and is
# NOT public (no Caddy vhost, not in DNS). To let a local app / iOS Simulator
# reach it at http://localhost:5281, forward the port over SSH. Production needs
# no tunnel (it is public at https://api.meerkat.tnisoft.ro).
#
# Usage:
#   vps1-meerkat-tunnel.sh up       # open the tunnel (idempotent)
#   vps1-meerkat-tunnel.sh down     # close the tunnel
#   vps1-meerkat-tunnel.sh status   # show whether it is up + dev health
#
# Aliases: v1-meerkat-tunnel-up (= up), v1-meerkat-tunnel-down (= down).
set -euo pipefail

#######################################
# Static config
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
MEERKAT_DEV_PORT="${MEERKAT_DEV_PORT:-5281}"
MEERKAT_DEV_REMOTE="${MEERKAT_DEV_REMOTE:-127.0.0.1:${MEERKAT_DEV_PORT}}"
MEERKAT_DEV_HEALTH_URL="http://localhost:${MEERKAT_DEV_PORT}/healthz"
FORWARD_SPEC="127.0.0.1:${MEERKAT_DEV_PORT}:${MEERKAT_DEV_REMOTE}"

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

listener_pids() {
  # PIDs of ssh processes holding this local listener.
  lsof -nP -a -c ssh -tiTCP:"${MEERKAT_DEV_PORT}" -sTCP:LISTEN 2>/dev/null || true
}

port_listener_pids() {
  # Any process holding the local listener, used to detect conflicts.
  lsof -nP -tiTCP:"${MEERKAT_DEV_PORT}" -sTCP:LISTEN 2>/dev/null || true
}

is_listening() {
  lsof -nP -iTCP:"${MEERKAT_DEV_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

dev_health() {
  curl -sS -m 5 "${MEERKAT_DEV_HEALTH_URL}" 2>/dev/null || true
}

dev_health_ok() {
  local health
  health="$(dev_health)"
  [[ "${health}" == *'"status": "ok"'* || "${health}" == *'"status":"ok"'* ]]
}

open_tunnel() {
  log "Opening tunnel localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE} ..."
  ssh -f -N -o ExitOnForwardFailure=yes -L "${FORWARD_SPEC}" "${VPS1_SSH_HOST}" \
    || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
  sleep 1
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_listening; then
    if dev_health_ok; then
      log "Tunnel already up — localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE}"
    else
      local pids; pids="$(listener_pids)"
      if [[ -z "${pids}" ]]; then
        local owners; owners="$(port_listener_pids)"
        die "Port ${MEERKAT_DEV_PORT} is in use but dev /healthz is unreachable. Listener pid(s): ${owners//$'\n'/ }."
      fi
      log "Stale Meerkat tunnel found (ssh pid: ${pids//$'\n'/ }) — restarting it ..."
      # shellcheck disable=SC2086
      kill ${pids}
      sleep 1
      if is_listening; then
        die "Port ${MEERKAT_DEV_PORT} is still in use after closing stale tunnel."
      fi
      open_tunnel
    fi
  else
    open_tunnel
  fi

  local health
  health="$(dev_health)"
  if [[ "${health}" == *'"status": "ok"'* || "${health}" == *'"status":"ok"'* ]]; then
    echo "✔ Dev API reachable at ${MEERKAT_DEV_HEALTH_URL}"
  else
    echo "⚠ Tunnel listener exists but dev /healthz did not report ok."
    [[ -n "${health}" ]] && echo "  ${health}"
  fi
  local pids; pids="$(listener_pids)"
  [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: v1-meerkat-tunnel-down"
}

tunnel_down() {
  local pids; pids="$(listener_pids)"
  if [[ -z "${pids}" ]]; then
    log "No Meerkat dev SSH tunnel found (nothing to close)."
    if is_listening; then
      local owners; owners="$(port_listener_pids)"
      echo "  Port ${MEERKAT_DEV_PORT} is still used by pid(s): ${owners//$'\n'/ }"
    fi
    return 0
  fi
  log "Closing tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  if is_listening; then
    die "Port ${MEERKAT_DEV_PORT} still in use after closing — check 'lsof -iTCP:${MEERKAT_DEV_PORT}'."
  fi
  echo "✔ Tunnel closed."
}

tunnel_status() {
  if is_listening; then
    local pids; pids="$(listener_pids)"
    local health; health="$(dev_health)"
    if [[ "${health}" == *'"status": "ok"'* || "${health}" == *'"status":"ok"'* ]]; then
      echo "● UP — localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE}${pids:+  (ssh pid: ${pids//$'\n'/ })}"
      echo "  health: ${health}"
    else
      echo "◐ BROKEN — listener exists on localhost:${MEERKAT_DEV_PORT}, but dev /healthz is unreachable or not ok.${pids:+  (ssh pid: ${pids//$'\n'/ })}"
      [[ -n "${health}" ]] && echo "  health: ${health}"
      echo "  Run: v1-meerkat-tunnel-up"
    fi
  else
    echo "○ DOWN — no listener on localhost:${MEERKAT_DEV_PORT}. Open with: v1-meerkat-tunnel-up"
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
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "Unknown action '${action}'. Use: up | down | status"
    ;;
esac
