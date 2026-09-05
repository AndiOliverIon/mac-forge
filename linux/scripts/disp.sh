#!/usr/bin/env bash

set -euo pipefail

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

[[ "${XDG_CURRENT_DESKTOP:-}" == *Hyprland* ]] \
    || die "A Hyprland session is required; detected desktop: ${XDG_CURRENT_DESKTOP:-unknown}."

require_command hyprctl
require_command fzf
require_command jq

monitor_json="$(hyprctl monitors -j)"
[[ -n "${monitor_json}" ]] || die "Hyprland returned no monitor information."

mapfile -t internal_monitors < <(
    jq -r '.[] | select((.name | test("^(eDP|LVDS|DSI)"))) | .name' <<< "${monitor_json}"
)
mapfile -t external_monitors < <(
    jq -r '.[] | select((.name | test("^(eDP|LVDS|DSI)") | not)) | .name' <<< "${monitor_json}"
)

all_monitors=("${internal_monitors[@]}" "${external_monitors[@]}")
((${#all_monitors[@]} > 0)) || die "No connected monitors detected."

choice="$(printf '%s\n' 'All' 'Laptop only' 'External only' \
    | fzf --prompt='Display layout > ' --height=40% --reverse)"

[[ -n "${choice}" ]] || {
    echo "Cancelled."
    exit 0
}

enable_monitor() {
    local monitor="$1"
    hyprctl keyword monitor "${monitor},preferred,auto,auto" > /dev/null
}

disable_monitor() {
    local monitor="$1"
    hyprctl keyword monitor "${monitor},disable" > /dev/null
}

case "${choice}" in
    All)
        for monitor in "${all_monitors[@]}"; do
            enable_monitor "${monitor}"
        done
        ;;
    'Laptop only')
        ((${#internal_monitors[@]} > 0)) || die "No internal display detected."
        for monitor in "${internal_monitors[@]}"; do
            enable_monitor "${monitor}"
        done
        for monitor in "${external_monitors[@]}"; do
            disable_monitor "${monitor}"
        done
        ;;
    'External only')
        ((${#external_monitors[@]} > 0)) || die "No external display detected."
        for monitor in "${external_monitors[@]}"; do
            enable_monitor "${monitor}"
        done
        for monitor in "${internal_monitors[@]}"; do
            disable_monitor "${monitor}"
        done
        ;;
    *)
        die "Unknown display choice: ${choice}"
        ;;
esac

echo "Applied '${choice}' for the current Hyprland session."
echo "Persist monitor behavior in ~/.config/hypr/monitors.lua."
