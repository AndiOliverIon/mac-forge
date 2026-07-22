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
  df -hT / | awk 'NR==2 {print $1 "\n" $2 "\n" $3 "\n" $5 "\n" $4 "\n" $6}'
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
  local -n left_lines="$left_name"
  local -n right_lines="$right_name"
  local row
  local row_count="${#left_lines[@]}"

  if (( ${#right_lines[@]} > row_count )); then
    row_count="${#right_lines[@]}"
  fi

  printf '%-56s%s\n' "$left_title" "$right_title"
  for ((row = 0; row < row_count; row++)); do
    printf '  %-54s  %s\n' "${left_lines[row]:-}" "${right_lines[row]:-}"
  done
  printf '\n'
}

readarray -t STORAGE_INFO < <(storage_lines)
readarray -t MEMORY_INFO < <(memory_lines)
DISK_NAME="${STORAGE_INFO[0]:-unknown}"
FILESYSTEM="${STORAGE_INFO[1]:-unknown}"
TOTAL_STORAGE="${STORAGE_INFO[2]:-unknown}"
FREE_STORAGE="${STORAGE_INFO[3]:-unknown}"
USED_STORAGE="${STORAGE_INFO[4]:-unknown}"
USED_PERCENT="${STORAGE_INFO[5]:-unknown}"
TOTAL_MEMORY="${MEMORY_INFO[0]:-unknown}"
USED_MEMORY="${MEMORY_INFO[1]:-unknown}"
AVAILABLE_MEMORY="${MEMORY_INFO[2]:-unknown}"
CPU_EFFORT="$(cpu_effort_line || true)"
CPU_TEMP="$(cpu_temp_line || true)"
CPU_MODEL="$(cpu_model_line || true)"
OS_NAME="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" || printf 'Linux')"

BATTERY_INFO=()
readarray -t BATTERY_INFO < <(battery_lines || true)
if (( ${#BATTERY_INFO[@]} > 0 )); then
  BATTERY_PRESENT=true
else
  BATTERY_PRESENT=false
fi

SYSTEM_LINES=(
  "OS          $OS_NAME"
  "Kernel      $(uname -r)"
  "Hostname    $(hostname)"
  "Uptime      $(uptime -p | sed 's/^up //')"
)
CPU_LINES=(
  "Model       ${CPU_MODEL:-Unavailable}"
  "Load        $(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)"
  "Effort      ${CPU_EFFORT:-Unavailable}"
  "Temperature ${CPU_TEMP:-Unavailable}"
)
MEMORY_LINES=(
  "Total       $TOTAL_MEMORY"
  "Available   $AVAILABLE_MEMORY"
  "Used        $USED_MEMORY"
)
STORAGE_LINES=(
  "Device      $DISK_NAME"
  "Filesystem  $FILESYSTEM"
  "Total       $TOTAL_STORAGE"
  "Free        $FREE_STORAGE"
  "Occupied    $USED_STORAGE ($USED_PERCENT)"
)

printf '\n'
printf 'Forge Linux Info\n'
printf '================\n'
printf '\n'
print_columns System SYSTEM_LINES CPU CPU_LINES
print_columns Memory MEMORY_LINES Storage STORAGE_LINES
printf 'Battery\n'
if [[ "$BATTERY_PRESENT" == true ]]; then
  printf '  Charge      %s%%\n' "${BATTERY_INFO[0]:-unknown}"
  printf '  Status      %s\n' "${BATTERY_INFO[1]:-unknown}"
  printf '  Cycle count %s\n' "${BATTERY_INFO[2]:-Unavailable}"
  printf '  Health      %s\n' "${BATTERY_INFO[3]:-Unavailable}"
else
  printf '  No battery (desktop or not available).\n'
fi
printf '\n'
