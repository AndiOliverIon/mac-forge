#!/usr/bin/env bash
# sudo-session.sh — toggle a passwordless-sudo window for this station.
#
# While enabled, oliver can run any sudo command without a password prompt.
# This is meant for short, deliberate experimentation windows (e.g. letting
# an AI agent run sudo commands) on this machine only — it has no effect on
# git, SSH, or any remote/online credential.
#
# The rule lives at /etc/sudoers.d/passwordless-session and is inert by
# default (renamed to *.disabled). Turning it on/off always requires one
# sudo password prompt — that prompt is the safety gate.
#
# Usage:
#   sudo-session.sh --on       # enable passwordless sudo
#   sudo-session.sh --off      # disable passwordless sudo (back to normal)
#   sudo-session.sh --status   # show current state
#
# Alias: sp --on | sp --off | sp --status
set -euo pipefail

RULE_ACTIVE="/etc/sudoers.d/passwordless-session"
RULE_DISABLED="/etc/sudoers.d/passwordless-session.disabled"

die() { echo "✖ $*" >&2; exit 1; }

# Re-exec under sudo so the caller doesn't need to type `sudo sp ...`.
if [[ ${EUID} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

session_on() {
  if [[ -f "${RULE_ACTIVE}" ]]; then
    echo "● Passwordless sudo already ENABLED."
    return 0
  fi
  [[ -f "${RULE_DISABLED}" ]] || die "No rule found at ${RULE_DISABLED}. Run the one-time setup first."
  mv "${RULE_DISABLED}" "${RULE_ACTIVE}"
  chmod 440 "${RULE_ACTIVE}"
  visudo -c -f "${RULE_ACTIVE}" >/dev/null || { mv "${RULE_ACTIVE}" "${RULE_DISABLED}"; die "Rule failed validation — reverted."; }
  echo "● Passwordless sudo ENABLED for this session. Disable with: sp --off"
}

session_off() {
  if [[ -f "${RULE_ACTIVE}" ]]; then
    mv "${RULE_ACTIVE}" "${RULE_DISABLED}"
  fi
  echo "○ Passwordless sudo DISABLED."
}

session_status() {
  if [[ -f "${RULE_ACTIVE}" ]]; then
    echo "● ENABLED — passwordless sudo is active. Disable with: sp --off"
  else
    echo "○ DISABLED — normal sudo (password required). Enable with: sp --on"
  fi
}

action="${1:-status}"
case "${action}" in
  on|--on)         session_on ;;
  off|--off)       session_off ;;
  status|--status) session_status ;;
  -h|--help|help)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "Unknown action '${action}'. Use: --on | --off | --status"
    ;;
esac
