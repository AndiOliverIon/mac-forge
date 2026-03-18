#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LINUX_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/forge.sh"

usage() {
  cat <<EOF
Usage:
  $0 [--config <path>] [apply|p|-P|remove|r|-R|status|s]

Defaults:
  - Config path: \$FORGE_HOME_ROOT/local-overrides.json
  - Fallback:    ${LINUX_ROOT}/config/local-overrides.example.json

Notes:
  - Delegates to the shared patch runtime to keep Linux behavior aligned with mac-forge.
EOF
}

CONFIG_FILE_DEFAULT="${FORGE_HOME_ROOT}/local-overrides.json"
CONFIG_FILE_EXAMPLE="${LINUX_ROOT}/config/local-overrides.example.json"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--config" ]]; then
  [[ -n "${2:-}" ]] || {
    usage
    forge_die "Missing value for --config"
  }

  if [[ "$2" = /* ]]; then
    CONFIG_FILE="$2"
  else
    CONFIG_FILE="$PWD/$2"
  fi

  shift 2
else
  CONFIG_FILE="$CONFIG_FILE_DEFAULT"

  if [[ ! -f "$CONFIG_FILE_DEFAULT" && -f "$CONFIG_FILE_EXAMPLE" ]]; then
    CONFIG_FILE="$CONFIG_FILE_EXAMPLE"
  fi
fi

exec "${LINUX_ROOT}/../scripts/patch.sh" --config "$CONFIG_FILE" "${@:-}"
