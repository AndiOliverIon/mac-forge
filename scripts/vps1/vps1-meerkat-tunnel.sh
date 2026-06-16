#!/opt/homebrew/bin/bash
# vps1-meerkat-tunnel.sh — open/close the SSH tunnel to the private Meerkat dev API.
#
# The dev endpoint binds to 127.0.0.1:8780 on vps1. To let a local app reach it
# at http://localhost:8780, forward the port over SSH.
#
# Usage:
#   vps1-meerkat-tunnel.sh up       # open the tunnel (idempotent)
#   vps1-meerkat-tunnel.sh down     # close the tunnel
#   vps1-meerkat-tunnel.sh status   # show whether it is up
#
# Aliases: v1-meerkat-tunnel-up (= up), v1-meerkat-tunnel-down (= down).
set -euo pipefail

#######################################
# Static config
#######################################
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
MEERKAT_DEV_PORT="${MEERKAT_DEV_PORT:-8780}"
MEERKAT_DEV_REMOTE="${MEERKAT_DEV_REMOTE:-127.0.0.1:${MEERKAT_DEV_PORT}}"
FORWARD_SPEC="${MEERKAT_DEV_PORT}:${MEERKAT_DEV_REMOTE}"

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
  lsof -nP -iTCP:"${MEERKAT_DEV_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_up; then
    log "Tunnel already up — localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE}"
  else
    log "Opening tunnel localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE} ..."
    ssh -f -N -L "${FORWARD_SPEC}" "${VPS1_SSH_HOST}" \
      || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
    sleep 1
  fi

  if is_up; then
    echo "✔ Tunnel reachable at localhost:${MEERKAT_DEV_PORT}"
    local pids; pids="$(listener_pids)"
    [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: v1-meerkat-tunnel-down"
  else
    die "Tunnel did not come up on localhost:${MEERKAT_DEV_PORT}."
  fi
}

tunnel_down() {
  local pids; pids="$(listener_pids)"
  if [[ -z "${pids}" ]]; then
    log "No Meerkat dev tunnel found (nothing to close)."
    return 0
  fi
  log "Closing tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  if is_up; then
    die "Port ${MEERKAT_DEV_PORT} still in use after closing — check 'lsof -iTCP:${MEERKAT_DEV_PORT}'."
  fi
  echo "✔ Tunnel closed."
}

tunnel_status() {
  if is_up; then
    local pids; pids="$(listener_pids)"
    echo "● UP — localhost:${MEERKAT_DEV_PORT} → ${VPS1_SSH_HOST}:${MEERKAT_DEV_REMOTE}${pids:+  (ssh pid: ${pids//$'\n'/ })}"
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
