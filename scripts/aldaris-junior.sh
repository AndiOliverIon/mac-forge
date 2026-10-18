#!/usr/bin/env bash
set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$FORGE_ROOT/config-local"
STATE_FILE="$STATE_DIR/aldaris-junior.state"

is_enabled() {
    [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == enabled ]]
}

case "${1:-status}" in
    on|off)
        [[ $# -eq 1 ]] || { echo 'Usage: junior on|off|status' >&2; exit 2; }
        umask 077
        mkdir -p "$STATE_DIR"
        temporary="$(mktemp "$STATE_DIR/.aldaris-junior.XXXXXX")"
        trap 'rm -f "$temporary"' EXIT
        if [[ "$1" == on ]]; then printf 'enabled\n' > "$temporary"; else printf 'disabled\n' > "$temporary"; fi
        mv "$temporary" "$STATE_FILE"
        "$0" status
        ;;
    status)
        if is_enabled; then
            echo 'Aldaris junior: ON — assistant delegation is enabled within the configured complexity limit.'
        else
            echo 'Aldaris junior: OFF — assistants work without Aldaris. Manual aldaris sessions remain available.'
        fi
        ;;
    check)
        is_enabled
        ;;
    *)
        echo 'Usage: junior on|off|status' >&2
        exit 2
        ;;
esac
