#!/usr/bin/env bash
# vps1-license-tunnel.sh — open/close the SSH tunnel to CodeMeter on vps1.
#
# CodeMeter binds to 127.0.0.1:22350 on vps1 and is not exposed publicly.
# Local Docker services can reach the forwarded license server through
# host.docker.internal:22350 while this tunnel is up.
#
# Usage:
#   vps1-license-tunnel.sh up       # open the tunnel (idempotent)
#   vps1-license-tunnel.sh down     # close the tunnel
#   vps1-license-tunnel.sh status   # show whether it is up
#
# Aliases: v1-license-tunnel-up, v1-license-tunnel-down, v1-license-tunnel-status.
set -euo pipefail

#######################################
# Static config
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
LICENSE_LOCAL_PORT="${LICENSE_LOCAL_PORT:-22350}"
LICENSE_REMOTE="${LICENSE_REMOTE:-127.0.0.1:22350}"
FORWARD_SPEC="127.0.0.1:${LICENSE_LOCAL_PORT}:${LICENSE_REMOTE}"

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

listener_pids() {
  lsof -nP -a -c ssh -tiTCP:"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null || true
}

port_listener_pids() {
  lsof -nP -tiTCP:"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null || true
}

is_listening() {
  lsof -nP -iTCP@127.0.0.1:"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

license_server_reachable() {
  nc -z -w 3 127.0.0.1 "${LICENSE_LOCAL_PORT}" >/dev/null 2>&1
}

open_tunnel() {
  log "Opening license tunnel localhost:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE} ..."
  ssh -f -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o BatchMode=yes \
    -L "${FORWARD_SPEC}" \
    "${VPS1_SSH_HOST}" \
    || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
  sleep 1
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_listening; then
    local pids
    pids="$(listener_pids)"
    if [[ -z "${pids}" ]]; then
      local owners
      owners="$(port_listener_pids)"
      die "Port ${LICENSE_LOCAL_PORT} is already used by a non-tunnel process. Listener pid(s): ${owners//$'\n'/ }."
    fi
    log "License tunnel already up — localhost:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE}"
  else
    open_tunnel
  fi

  if license_server_reachable; then
    echo "✔ CodeMeter reachable at localhost:${LICENSE_LOCAL_PORT}"
    local pids
    pids="$(listener_pids)"
    [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: v1-license-tunnel-down"
  else
    die "Tunnel listener exists, but CodeMeter is not reachable through it."
  fi
}

tunnel_down() {
  local pids
  pids="$(listener_pids)"
  if [[ -z "${pids}" ]]; then
    log "No vps1 license tunnel found (nothing to close)."
    if is_listening; then
      local owners
      owners="$(port_listener_pids)"
      echo "  Port ${LICENSE_LOCAL_PORT} is still used by pid(s): ${owners//$'\n'/ }"
    fi
    return 0
  fi

  log "Closing license tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  if is_listening; then
    die "Port ${LICENSE_LOCAL_PORT} still in use after closing — check 'lsof -iTCP:${LICENSE_LOCAL_PORT}'."
  fi
  echo "✔ License tunnel closed."
}

tunnel_status() {
  if is_listening; then
    local pids
    pids="$(listener_pids)"
    if [[ -n "${pids}" ]] && license_server_reachable; then
      echo "● UP — localhost:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE}  (ssh pid: ${pids//$'\n'/ })"
    elif [[ -n "${pids}" ]]; then
      echo "◐ BROKEN — SSH listener exists on localhost:${LICENSE_LOCAL_PORT}, but CodeMeter is not reachable."
    else
      local owners
      owners="$(port_listener_pids)"
      echo "◐ CONFLICT — localhost:${LICENSE_LOCAL_PORT} is used by non-tunnel pid(s): ${owners//$'\n'/ }"
    fi
  else
    echo "○ DOWN — no listener on localhost:${LICENSE_LOCAL_PORT}. Open with: v1-license-tunnel-up"
  fi
}

#######################################
# Main
#######################################
action="${1:-status}"
case "${action}" in
  up|--up)         tunnel_up ;;
  down|--down)     tunnel_down ;;
  status|--status) tunnel_status ;;
  -h|--help|help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "Unknown action '${action}'. Use: up | down | status"
    ;;
esac
