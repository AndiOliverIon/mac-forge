#!/usr/bin/env bash
# hades-tunnel.sh — open/close the SSH tunnel from a Linux station to Hades.
#
# When the Angular and Perform API development servers run on Hades, this
# exposes them to the local Linux station (e.g. masterchief) over the LAN.
# While the tunnel is up the services are reachable at:
#   http://localhost:4200  (Angular)
#   http://localhost:8080  (Perform API)
#
# Hades must have Remote Login (sshd) enabled and key-based SSH access must work
# from this station. The tunnel connects through the `hades` SSH host alias by
# default; set HADES_SSH_HOST to override it (e.g. hades).
#
# Usage:
#   hades-tunnel.sh up       # open the tunnel (idempotent)
#   hades-tunnel.sh down     # close the tunnel
#   hades-tunnel.sh status   # show whether it is up
#
# Aliases: hades-tunnel-up, hades-tunnel-down, hades-tunnel-status.
set -euo pipefail

#######################################
# Static config
#######################################
HADES_SSH_HOST="${HADES_SSH_HOST:-hades}"
HADES_LOCAL_BIND="${HADES_LOCAL_BIND:-127.0.0.1}"
HADES_TUNNEL_PORTS="${HADES_TUNNEL_PORTS:-4200 8080}"
read -r -a PORTS <<<"${HADES_TUNNEL_PORTS}"

FORWARD_ARGS=()
for port in "${PORTS[@]}"; do
  FORWARD_ARGS+=(-L "${HADES_LOCAL_BIND}:${port}:localhost:${port}")
done

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }

# ssh-owned listeners on a port (our tunnel).
tunnel_pids_on() {
  lsof -nP -a -c ssh -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | sort -u || true
}

# any listener on a port (used to detect conflicts).
any_pids_on() {
  lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | sort -u || true
}

is_tunnel_listening_on() {
  [[ -n "$(tunnel_pids_on "$1")" ]]
}

# pids of the ssh processes that own every forwarded port (the live tunnel).
all_tunnel_pids() {
  local first=1 pids acc=""
  for port in "${PORTS[@]}"; do
    pids="$(tunnel_pids_on "${port}")"
    [[ -z "${pids}" ]] && { echo ""; return; }
    if [[ ${first} -eq 1 ]]; then
      acc="${pids}"
      first=0
    else
      acc="$(comm -12 <(echo "${acc}") <(echo "${pids}"))"
    fi
  done
  echo "${acc}" | sort -u | sed '/^$/d'
}

fully_up() {
  for port in "${PORTS[@]}"; do
    is_tunnel_listening_on "${port}" || return 1
  done
  return 0
}

any_tunnel_up() {
  for port in "${PORTS[@]}"; do
    is_tunnel_listening_on "${port}" && return 0
  done
  return 1
}

conflict_ports() {
  local out=""
  for port in "${PORTS[@]}"; do
    if [[ -n "$(any_pids_on "${port}")" && -z "$(tunnel_pids_on "${port}")" ]]; then
      out+="${port} "
    fi
  done
  echo "${out}"
}

open_tunnel() {
  log "Opening Hades tunnel ${HADES_LOCAL_BIND}:{${HADES_TUNNEL_PORTS// /,}} → ${HADES_SSH_HOST} ..."
  ssh -f -N \
    -o ExitOnForwardFailure=yes \
    -o IdentitiesOnly=yes \
    -o ServerAliveInterval=30 \
    -o BatchMode=yes \
    "${FORWARD_ARGS[@]}" \
    "${HADES_SSH_HOST}" \
    || die "Failed to open SSH tunnel to ${HADES_SSH_HOST}. Verify: ssh ${HADES_SSH_HOST}"
  sleep 1
}

#######################################
# Actions
#######################################
tunnel_up() {
  local conflicts
  conflicts="$(conflict_ports)"
  [[ -n "${conflicts}" ]] && die "Port(s) ${conflicts}already used by a non-tunnel process."

  if fully_up; then
    log "Hades tunnel already up — localhost:${HADES_TUNNEL_PORTS// /, localhost:}"
  else
    # Clear any stale partial tunnel before reopening.
    local stale
    stale="$(all_tunnel_pids)"
    if [[ -n "${stale}" ]]; then
      log "Clearing a stale/partial Hades tunnel ..."
      # shellcheck disable=SC2086
      kill ${stale} 2>/dev/null || true
      sleep 1
    fi
    open_tunnel
  fi

  fully_up || die "The Hades tunnel did not open on all ports (${HADES_TUNNEL_PORTS})."
  local pids
  pids="$(all_tunnel_pids)"
  echo "✔ Hades services available at localhost:${HADES_TUNNEL_PORTS// /, localhost:}"
  [[ -n "${pids}" ]] && echo "  (ssh pid: ${pids//$'\n'/ })  — close with: hades-tunnel-down"
}

tunnel_down() {
  local pids
  pids="$(all_tunnel_pids)"
  if [[ -z "${pids}" ]]; then
    # Fall back to any ssh listener on our ports (covers partial tunnels).
    local acc=""
    for port in "${PORTS[@]}"; do
      acc+="$(tunnel_pids_on "${port}") "
    done
    pids="$(echo "${acc}" | tr ' ' '\n' | sort -u | sed '/^$/d')"
  fi

  if [[ -z "${pids}" ]]; then
    log "No Hades tunnel found (nothing to close)."
    return 0
  fi

  log "Closing Hades tunnel (ssh pid: ${pids//$'\n'/ }) ..."
  # shellcheck disable=SC2086
  kill ${pids}
  sleep 1
  for port in "${PORTS[@]}"; do
    if is_tunnel_listening_on "${port}"; then
      die "Port ${port} still listening after closing — check 'lsof -iTCP:${port}'."
    fi
  done
  echo "✔ Hades tunnel closed."
}

tunnel_status() {
  local conflicts
  conflicts="$(conflict_ports)"
  if fully_up; then
    local pids
    pids="$(all_tunnel_pids)"
    echo "● UP — localhost:${HADES_TUNNEL_PORTS// /, localhost:} → ${HADES_SSH_HOST}  (ssh pid: ${pids//$'\n'/ })"
  elif [[ -n "${conflicts}" ]]; then
    echo "◐ CONFLICT — port(s) ${conflicts}used by a non-tunnel process."
  elif any_tunnel_up; then
    echo "◐ PARTIAL — the tunnel is up on some ports only. Reopen with: hades-tunnel-up"
  else
    echo "○ DOWN — no Hades tunnel. Open with: hades-tunnel-up"
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
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "Unknown action '${action}'. Use: up | down | status"
    ;;
esac
