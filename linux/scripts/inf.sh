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
  df -h / | awk 'NR==2 {print $2 "\n" $4 "\n" $3 "\n" $5}'
}

readarray -t STORAGE_INFO < <(storage_lines)
TOTAL_STORAGE="${STORAGE_INFO[0]:-unknown}"
FREE_STORAGE="${STORAGE_INFO[1]:-unknown}"
USED_STORAGE="${STORAGE_INFO[2]:-unknown}"
USED_PERCENT="${STORAGE_INFO[3]:-unknown}"
CPU_EFFORT="$(cpu_effort_line || true)"
CPU_TEMP="$(cpu_temp_line || true)"

printf '\n'
printf 'Forge Linux Info\n'
printf '================\n'
printf '\n'
printf 'System\n'
printf '  Uptime      %s\n' "$(uptime -p | sed 's/^up //')"
printf '\n'
printf 'CPU\n'
printf '  Effort      %s\n' "${CPU_EFFORT:-Unavailable}"
printf '  Temperature %s\n' "${CPU_TEMP:-Unavailable}"
printf '\n'
printf 'Storage\n'
printf '  Total       %s\n' "${TOTAL_STORAGE}"
printf '  Free        %s\n' "${FREE_STORAGE}"
printf '  Occupied    %s (%s)\n' "${USED_STORAGE}" "${USED_PERCENT}"
printf '\n'
