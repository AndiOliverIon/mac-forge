#!/usr/bin/env bash
set -euo pipefail

cpu_effort_line() {
  top -bn1 2>/dev/null | awk -F ', *' '/^%Cpu/ {
    user=$1
    sys=$2
    gsub(/^[^0-9.]*/, "", user)
    gsub(/[^0-9.].*$/, "", user)
    gsub(/^[^0-9.]*/, "", sys)
    gsub(/[^0-9.].*$/, "", sys)
    if (user != "" && sys != "") {
      printf "%s%% user, %s%% sys", user, sys
      exit
    }
  }'
}

friendly_uptime() {
  uptime -p | sed -E 's/^up //; s/, ([0-9]+ minutes?)$/ \1/'
}

cpu_model_line() {
  awk -F: '/^model name[[:space:]]*:/ {
    value=$2
    sub(/^[[:space:]]+/, "", value)
    print value
    exit
  }' /proc/cpuinfo 2>/dev/null
}

cpu_temp_line() {
  local temp_raw

  if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp_raw="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true)"
    if [[ "$temp_raw" =~ ^[0-9]+$ ]]; then
      awk -v value="$temp_raw" 'BEGIN { printf "%.1f C", value / 1000 }'
      return 0
    fi
  fi

  if command -v sensors >/dev/null 2>&1; then
    sensors 2>/dev/null | awk '
      /\+([0-9]+(\.[0-9]+)?)°C/ {
        match($0, /\+([0-9]+(\.[0-9]+)?)°C/, parts)
        if (parts[1] != "") {
          printf "%s C", parts[1]
          exit
        }
      }'
    return 0
  fi

  printf 'Unavailable'
}

storage_lines() {
  local path="${1:-/}"

  df -hT "$path" | awk 'NR==2 {print $1 "\n" $2 "\n" $3 "\n" $5 "\n" $4 "\n" $6}'
}

memory_lines() {
  free -h 2>/dev/null | awk '/^Mem:/ {print $2 "\n" $3 "\n" $7}'
}

battery_lines() {
  local battery
  local full_capacity
  local design_capacity
  local health_state

  for battery in /sys/class/power_supply/BAT*; do
    [[ -d "$battery" ]] || continue
    printf '%s\n' "$(cat "$battery/capacity" 2>/dev/null || printf 'unknown')"
    printf '%s\n' "$(cat "$battery/status" 2>/dev/null || printf 'unknown')"
    if [[ -r "$battery/cycle_count" ]]; then
      cat "$battery/cycle_count" 2>/dev/null || printf 'unknown\n'
    else
      printf 'Unavailable\n'
    fi

    full_capacity="$(cat "$battery/charge_full" 2>/dev/null || cat "$battery/energy_full" 2>/dev/null || true)"
    design_capacity="$(cat "$battery/charge_full_design" 2>/dev/null || cat "$battery/energy_full_design" 2>/dev/null || true)"
    health_state="$(cat "$battery/health" 2>/dev/null || true)"
    if [[ "$full_capacity" =~ ^[0-9]+$ && "$design_capacity" =~ ^[1-9][0-9]*$ ]]; then
      awk -v full="$full_capacity" -v design="$design_capacity" -v state="$health_state" 'BEGIN {
        printf "%.1f%%", full / design * 100
        if (state != "") printf " (%s)", state
        printf "\n"
      }'
    elif [[ -n "$health_state" ]]; then
      printf '%s\n' "$health_state"
    else
      printf 'Unavailable\n'
    fi
    return 0
  done

  return 1
}

print_columns() {
  local left_title="$1"
  local left_name="$2"
  local right_title="$3"
  local right_name="$4"
  local left_color="$5"
  local right_color="$6"
  local -n left_lines="$left_name"
  local -n right_lines="$right_name"
  local terminal_width
  local left_width
  local right_width
  local row
  local row_count="${#left_lines[@]}"

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40
  left_width=$(( (terminal_width - 2) / 2 ))
  right_width=$(( terminal_width - left_width - 2 ))

  if (( ${#right_lines[@]} > row_count )); then
    row_count="${#right_lines[@]}"
  fi

  printf '%s%-*.*s%s  %s%-*.*s%s\n' \
    "$left_color" "$left_width" "$left_width" "$left_title" "$RESET" \
    "$right_color" "$right_width" "$right_width" "$right_title" "$RESET"
  for ((row = 0; row < row_count; row++)); do
    printf '%-*.*s  %-*.*s\n' \
      "$left_width" "$left_width" "${left_lines[row]:-}" \
      "$right_width" "$right_width" "${right_lines[row]:-}"
  done
}

print_info() {
  local disk_name
  local filesystem
  local total_storage
  local free_storage
  local used_storage
  local used_percent
  local total_memory
  local used_memory
  local available_memory
  local cpu_effort
  local cpu_temp
  local cpu_model
  local os_name
  local battery_present
  local battery_color
  local storage_color
  local storage_percent
  local data_storage_percent
  local -a storage_info
  local -a memory_info
  local -a battery_info
  local -a system_lines
  local -a cpu_lines
  local -a memory_lines
  local -a battery_lines
  local -a storage_lines
  local -a data_storage_info
  local terminal_width

  readarray -t storage_info < <(storage_lines /)
  readarray -t memory_info < <(memory_lines)
  disk_name="${storage_info[0]:-unknown}"
  filesystem="${storage_info[1]:-unknown}"
  total_storage="${storage_info[2]:-unknown}"
  free_storage="${storage_info[3]:-unknown}"
  used_storage="${storage_info[4]:-unknown}"
  used_percent="${storage_info[5]:-unknown}"
  total_memory="${memory_info[0]:-unknown}"
  used_memory="${memory_info[1]:-unknown}"
  available_memory="${memory_info[2]:-unknown}"
  cpu_effort="$(cpu_effort_line || true)"
  cpu_temp="$(cpu_temp_line || true)"
  cpu_model="$(cpu_model_line || true)"
  os_name="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" || printf 'Linux')"

  battery_info=()
  readarray -t battery_info < <(battery_lines || true)
  if (( ${#battery_info[@]} > 0 )); then
    battery_present=true
  else
    battery_present=false
  fi

  system_lines=(
    "OS       $os_name"
    "Host     $(hostname)"
    "Kernel   $(uname -r)"
    "Uptime   $(friendly_uptime)"
  )
  cpu_lines=(
    "Model    ${cpu_model:-Unavailable}"
    "Load     $(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)"
    "Effort   ${cpu_effort:-Unavailable} | Temp ${cpu_temp:-Unavailable}"
  )
  memory_lines=(
    "Total    $total_memory | Used $used_memory"
    "Free     $available_memory available"
  )

  if [[ "$battery_present" == true ]]; then
    battery_color="$GREEN"
    if [[ "${battery_info[0]:-}" =~ ^[0-9]+$ ]]; then
      if (( 10#${battery_info[0]} < 20 )); then
        battery_color="$RED"
      elif (( 10#${battery_info[0]} < 50 )); then
        battery_color="$YELLOW"
      fi
    fi
    battery_lines=(
      "Charge   ${battery_info[0]:-unknown}% | ${battery_info[1]:-unknown}"
      "Health   ${battery_info[3]:-Unavailable} | Cycles ${battery_info[2]:-Unavailable}"
    )
  else
    battery_color="$DIM"
    battery_lines=("No battery available")
  fi

  storage_color="$GREEN"
  storage_percent="${used_percent%\%}"
  if [[ "$storage_percent" =~ ^[0-9]+$ ]]; then
    if (( 10#$storage_percent >= 90 )); then
      storage_color="$RED"
    elif (( 10#$storage_percent >= 75 )); then
      storage_color="$YELLOW"
    fi
  fi
  storage_lines=(
    "/      $filesystem on $disk_name | $used_storage / $total_storage ($used_percent) | $free_storage free"
  )

  if mountpoint -q /data; then
    data_storage_info=()
    readarray -t data_storage_info < <(storage_lines /data)
    data_storage_percent="${data_storage_info[5]:-0}"
    data_storage_percent="${data_storage_percent%\%}"
    if [[ "$data_storage_percent" =~ ^[0-9]+$ ]]; then
      if (( 10#$data_storage_percent >= 90 )); then
        storage_color="$RED"
      elif (( 10#$data_storage_percent >= 75 )) && [[ "$storage_color" != "$RED" ]]; then
        storage_color="$YELLOW"
      fi
    fi
    storage_lines+=(
      "/data  ${data_storage_info[1]:-unknown} on ${data_storage_info[0]:-unknown} | ${data_storage_info[4]:-unknown} / ${data_storage_info[2]:-unknown} (${data_storage_info[5]:-unknown}) | ${data_storage_info[3]:-unknown} free"
    )
  fi

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '%sForge Linux Info%s\n\n' "$BOLD" "$RESET"
  print_columns '● System' system_lines '◆ CPU' cpu_lines "$BLUE" "$CYAN"
  printf '\n'
  print_columns '▣ Memory' memory_lines '♥ Battery' battery_lines "$MAGENTA" "$battery_color"
  printf '\n%s■ Storage%s\n' "$storage_color" "$RESET"
  printf '%.*s\n' "$terminal_width" "${storage_lines[0]}"
  if (( ${#storage_lines[@]} > 1 )); then
    printf '%.*s\n' "$terminal_width" "${storage_lines[1]}"
  fi
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
