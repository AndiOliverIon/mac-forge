#!/usr/bin/env bash
# vps1-license-tunnel.sh — open/close the SSH tunnel to CodeMeter on vps1.
#
# CodeMeter binds to 127.0.0.1:22350 on vps1 and is not exposed publicly.
# Local Docker services can reach the forwarded license server through
# host.docker.internal:22350 while this tunnel is up. On macOS, the tunnel also
# binds to the private Parallels shared-network interface when it is available.
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
LICENSE_LOCAL_BIND="${LICENSE_LOCAL_BIND:-127.0.0.1}"
LICENSE_PARALLELS_BIND="${LICENSE_PARALLELS_BIND:-auto}"

if [[ "${LICENSE_PARALLELS_BIND}" == "auto" ]]; then
  LICENSE_PARALLELS_BIND=""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    LICENSE_PARALLELS_BIND="$(
      ifconfig bridge100 2>/dev/null | awk '$1 == "inet" { print $2; exit }' || true
    )"
  fi
elif [[ "${LICENSE_PARALLELS_BIND}" == "off" ]]; then
  LICENSE_PARALLELS_BIND=""
fi

LOCAL_FORWARD_SPEC="${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT}:${LICENSE_REMOTE}"
PARALLELS_FORWARD_SPEC=""
if [[ -n "${LICENSE_PARALLELS_BIND}" && "${LICENSE_PARALLELS_BIND}" != "${LICENSE_LOCAL_BIND}" ]]; then
  PARALLELS_FORWARD_SPEC="${LICENSE_PARALLELS_BIND}:${LICENSE_LOCAL_PORT}:${LICENSE_REMOTE}"
fi

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

listener_pids() {
  lsof -nP -a -c ssh -tiTCP:"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null | sort -u || true
}

port_listener_pids() {
  lsof -nP -tiTCP:"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null | sort -u || true
}

is_listening_at() {
  local address="$1"
  lsof -nP -iTCP@"${address}":"${LICENSE_LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1
}

license_server_reachable_at() {
  local address="$1"
  nc -z -w 3 "${address}" "${LICENSE_LOCAL_PORT}" >/dev/null 2>&1
}

open_tunnel() {
  local forward_args=(-L "${LOCAL_FORWARD_SPEC}")
  if [[ -n "${PARALLELS_FORWARD_SPEC}" ]]; then
    forward_args+=(-L "${PARALLELS_FORWARD_SPEC}")
  fi

  log "Opening license tunnel ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE} ..."
  if [[ -n "${PARALLELS_FORWARD_SPEC}" ]]; then
    log "Adding private Parallels listener ${LICENSE_PARALLELS_BIND}:${LICENSE_LOCAL_PORT}"
  fi

  ssh -f -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o BatchMode=yes \
    "${forward_args[@]}" \
    "${VPS1_SSH_HOST}" \
    || die "Failed to open SSH tunnel to ${VPS1_SSH_HOST}."
  sleep 1
}

#######################################
# Actions
#######################################
tunnel_up() {
  if is_listening_at "${LICENSE_LOCAL_BIND}"; then
    local pids
    pids="$(listener_pids)"
    if [[ -z "${pids}" ]]; then
      local owners
      owners="$(port_listener_pids)"
      die "Port ${LICENSE_LOCAL_PORT} is already used by a non-tunnel process. Listener pid(s): ${owners//$'\n'/ }."
    fi

    if [[ -n "${PARALLELS_FORWARD_SPEC}" ]] && ! is_listening_at "${LICENSE_PARALLELS_BIND}"; then
      log "Existing tunnel lacks the private Parallels listener — restarting it ..."
      # shellcheck disable=SC2086
      kill ${pids}
      sleep 1
      open_tunnel
    else
      log "License tunnel already up — ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE}"
    fi
  else
    open_tunnel
  fi

  if license_server_reachable_at "${LICENSE_LOCAL_BIND}"; then
    echo "✔ CodeMeter reachable at ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT}"
    if [[ -n "${PARALLELS_FORWARD_SPEC}" ]]; then
      if license_server_reachable_at "${LICENSE_PARALLELS_BIND}"; then
        echo "✔ CodeMeter reachable from Parallels via ${LICENSE_PARALLELS_BIND}:${LICENSE_LOCAL_PORT}"
      else
        die "The local tunnel works, but the private Parallels listener is not reachable."
      fi
    fi
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
    if is_listening_at "${LICENSE_LOCAL_BIND}"; then
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
  if is_listening_at "${LICENSE_LOCAL_BIND}" \
    || { [[ -n "${PARALLELS_FORWARD_SPEC}" ]] && is_listening_at "${LICENSE_PARALLELS_BIND}"; }; then
    die "Port ${LICENSE_LOCAL_PORT} still in use after closing — check 'lsof -iTCP:${LICENSE_LOCAL_PORT}'."
  fi
  echo "✔ License tunnel closed."
}

tunnel_status() {
  if is_listening_at "${LICENSE_LOCAL_BIND}"; then
    local pids
    pids="$(listener_pids)"
    if [[ -n "${pids}" ]] && license_server_reachable_at "${LICENSE_LOCAL_BIND}"; then
      if [[ -n "${PARALLELS_FORWARD_SPEC}" ]] && ! license_server_reachable_at "${LICENSE_PARALLELS_BIND}"; then
        echo "◐ PARTIAL — localhost works, but ${LICENSE_PARALLELS_BIND}:${LICENSE_LOCAL_PORT} is unavailable."
        return
      fi

      echo "● UP — ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT} → ${VPS1_SSH_HOST}:${LICENSE_REMOTE}  (ssh pid: ${pids//$'\n'/ })"
      if [[ -n "${PARALLELS_FORWARD_SPEC}" ]]; then
        echo "  Parallels: ${LICENSE_PARALLELS_BIND}:${LICENSE_LOCAL_PORT}"
      fi
    elif [[ -n "${pids}" ]]; then
      echo "◐ BROKEN — SSH listener exists on ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT}, but CodeMeter is not reachable."
    else
      local owners
      owners="$(port_listener_pids)"
      echo "◐ CONFLICT — ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT} is used by non-tunnel pid(s): ${owners//$'\n'/ }"
    fi
  else
    echo "○ DOWN — no listener on ${LICENSE_LOCAL_BIND}:${LICENSE_LOCAL_PORT}. Open with: v1-license-tunnel-up"
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
