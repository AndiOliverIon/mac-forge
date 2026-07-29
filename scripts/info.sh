#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
fi

format_size() {
  awk -v kib="$1" '
    BEGIN {
      bytes = kib * 1024
      split("B KB MB GB TB PB", units, " ")
      i = 1
      while (bytes >= 1000 && i < 6) {
        bytes /= 1000
        i++
      }
      printf "%.1f %s", bytes, units[i]
    }'
}

print_columns() {
  local left_title="$1"
  local right_title="$2"
  local left_color="$3"
  local right_color="$4"
  local terminal_width
  local left_width
  local right_width

  shift 4
  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40
  left_width=$(( (terminal_width - 2) / 2 ))
  right_width=$(( terminal_width - left_width - 2 ))

  printf '%s%-*.*s%s  %s%-*.*s%s\n' \
    "$left_color" "$left_width" "$left_width" "$left_title" "$RESET" \
    "$right_color" "$right_width" "$right_width" "$right_title" "$RESET"
  while (( $# >= 2 )); do
    printf '%-*.*s  %-*.*s\n' \
      "$left_width" "$left_width" "$1" \
      "$right_width" "$right_width" "$2"
    shift 2
  done
}

print_info() {
  local top_output
  local cpu_effort
  local phys_mem
  local used_memory
  local available_memory
  local total_memory_kib
  local disk_name
  local disk_total_kib
  local disk_used_kib
  local disk_free_kib
  local disk_percent
  local filesystem
  local os_name
  local kernel
  local host_name
  local uptime_value
  local cpu_model
  local cpu_load
  local battery_output
  local charge
  local charge_percent
  local status
  local power_info
  local cycles
  local max_capacity
  local condition
  local health
  local battery_color
  local storage_color
  local storage_percent
  local terminal_width
  local system_os
  local system_host
  local system_kernel
  local cpu_model_row
  local cpu_load_row
  local cpu_effort_row
  local memory_total
  local memory_free
  local battery_charge
  local battery_health
  local storage_row

  top_output="$(top -l 1 -n 0)"
  cpu_effort="$(printf '%s\n' "$top_output" | awk -F': ' '/CPU usage/ {
    split($2, values, ", *")
    printf "%s, %s", values[1], values[2]
    exit
  }')"
  phys_mem="$(printf '%s\n' "$top_output" | awk '/PhysMem/ {print; exit}')"
  used_memory="$(printf '%s\n' "$phys_mem" | sed -E 's/.*PhysMem: ([^ ]+) used.*/\1/')"
  available_memory="$(printf '%s\n' "$phys_mem" | sed -E 's/.*, ([^ ]+) unused.*/\1/')"
  total_memory_kib="$(( $(sysctl -n hw.memsize) / 1024 ))"

  read -r disk_name disk_total_kib disk_used_kib disk_free_kib disk_percent < <(
    df -k / | awk 'NR==2 {print $1, $2, $3, $4, $5}'
  )
  filesystem="$(diskutil info / 2>/dev/null \
    | awk -F: '/File System Personality/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

  os_name="$(sw_vers -productName) $(sw_vers -productVersion)"
  kernel="$(uname -r)"
  host_name="$(hostname)"
  uptime_value="$(uptime | awk -F'up ' '{print $2}' | sed 's/, [0-9] user.*//')"
  cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)"
  cpu_load="$(sysctl -n vm.loadavg | awk '{print $2 ", " $3 ", " $4}')"

  battery_output="$(pmset -g batt 2>/dev/null || true)"
  charge="$(printf '%s\n' "$battery_output" | grep -Eo '[0-9]+%' | head -n1 || true)"
  if [[ -n "$charge" ]]; then
    status="$(printf '%s\n' "$battery_output" \
      | awk -F';' '/[0-9]+%/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    power_info="$(system_profiler SPPowerDataType 2>/dev/null || true)"
    cycles="$(printf '%s\n' "$power_info" \
      | awk -F: '/Cycle Count/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    max_capacity="$(printf '%s\n' "$power_info" \
      | awk -F: '/Maximum Capacity/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    condition="$(printf '%s\n' "$power_info" \
      | awk -F: '/Condition/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

    health="${max_capacity:-Unavailable}"
    if [[ -n "$condition" && "$health" != 'Unavailable' ]]; then
      health="$health ($condition)"
    elif [[ -n "$condition" ]]; then
      health="$condition"
    fi

    battery_color="$GREEN"
    charge_percent="${charge%\%}"
    if [[ "$charge_percent" =~ ^[0-9]+$ ]]; then
      if (( 10#$charge_percent < 20 )); then
        battery_color="$RED"
      elif (( 10#$charge_percent < 50 )); then
        battery_color="$YELLOW"
      fi
    fi
    battery_charge="Charge   $charge | ${status:-unknown}"
    battery_health="Health   $health | Cycles ${cycles:-Unavailable}"
  else
    battery_color="$DIM"
    battery_charge="No battery available"
    battery_health=""
  fi

  storage_color="$GREEN"
  storage_percent="${disk_percent%\%}"
  if [[ "$storage_percent" =~ ^[0-9]+$ ]]; then
    if (( 10#$storage_percent >= 90 )); then
      storage_color="$RED"
    elif (( 10#$storage_percent >= 75 )); then
      storage_color="$YELLOW"
    fi
  fi

  system_os="OS       $os_name"
  system_host="Host     $host_name"
  system_kernel="Kernel   $kernel | Up $uptime_value"
  cpu_model_row="Model    ${cpu_model:-Unavailable}"
  cpu_load_row="Load     $cpu_load"
  cpu_effort_row="Effort   ${cpu_effort:-Unavailable} | Temp Unavailable"
  memory_total="Total    $(format_size "$total_memory_kib") | Used ${used_memory:-unknown}"
  memory_free="Free     ${available_memory:-unknown} available"
  storage_row="/      ${filesystem:-unknown} on $disk_name | $(format_size "$disk_used_kib") / $(format_size "$disk_total_kib") ($disk_percent) | $(format_size "$disk_free_kib") free"

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '%sForge macOS Info%s\n\n' "$BOLD" "$RESET"
  print_columns '● System' '◆ CPU' "$BLUE" "$CYAN" \
    "$system_os" "$cpu_model_row" \
    "$system_host" "$cpu_load_row" \
    "$system_kernel" "$cpu_effort_row"
  printf '\n'
  print_columns '▣ Memory' '♥ Battery' "$MAGENTA" "$battery_color" \
    "$memory_total" "$battery_charge" \
    "$memory_free" "$battery_health"
  printf '\n%s■ Storage%s\n' "$storage_color" "$RESET"
  printf '%.*s\n' "$terminal_width" "$storage_row"
}

BOLD=""
DIM=""
BLUE=""
CYAN=""
MAGENTA=""
GREEN=""
YELLOW=""
RED=""
RESET=""
if [[ -t 1 && -z "${NO_COLOR+x}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  MAGENTA=$'\033[35m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
fi

cycle_interval=""
if [[ "${1:-}" == "--cycle" ]]; then
  cycle_interval="${2:-5}"
  if [[ ! "$cycle_interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v value="$cycle_interval" 'BEGIN { exit !(value > 0) }'; then
    printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
    exit 2
  fi
  if (( $# > 2 )); then
    printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
    exit 2
  fi
elif (( $# > 0 )); then
  printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
  exit 2
fi

if [[ -n "$cycle_interval" ]]; then
  trap 'printf "\033[?25h"' EXIT
  printf '\033[?25l'
  while true; do
    snapshot="$(print_info)"
    printf '\033[H%s\n\033[J' "$snapshot"
    sleep "$cycle_interval"
  done
else
  print_info
fi
