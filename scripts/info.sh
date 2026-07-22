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

TOP_OUTPUT="$(top -l 1 -n 0)"
CPU_EFFORT="$(printf '%s\n' "$TOP_OUTPUT" | awk -F': ' '/CPU usage/ {print $2; exit}')"
PHYS_MEM="$(printf '%s\n' "$TOP_OUTPUT" | awk '/PhysMem/ {print; exit}')"
USED_MEMORY="$(printf '%s\n' "$PHYS_MEM" | sed -E 's/.*PhysMem: ([^ ]+) used.*/\1/')"
AVAILABLE_MEMORY="$(printf '%s\n' "$PHYS_MEM" | sed -E 's/.*, ([^ ]+) unused.*/\1/')"
TOTAL_MEMORY_KIB="$(( $(sysctl -n hw.memsize) / 1024 ))"

read -r DISK_NAME DISK_TOTAL_KIB DISK_USED_KIB DISK_FREE_KIB _ < <(
  df -k / | awk 'NR==2 {print $1, $2, $3, $4, $5}'
)
FILESYSTEM="$(diskutil info / 2>/dev/null \
  | awk -F: '/File System Personality/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

OS_NAME="$(sw_vers -productName) $(sw_vers -productVersion)"
KERNEL="$(uname -r)"
HOSTNAME="$(hostname)"
UPTIME="$(uptime | awk -F'up ' '{print $2}' | sed 's/, [0-9] user.*//')"
CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)"
CPU_LOAD="$(sysctl -n vm.loadavg | awk '{print $2 ", " $3 ", " $4}')"

printf '\n'
printf 'Forge macOS Info\n'
printf '================\n'
printf '\n'
printf '%-56s%s\n' 'System' 'CPU'
printf '  %-54s  %s\n' "OS          $OS_NAME" "Model       $CPU_MODEL"
printf '  %-54s  %s\n' "Kernel      $KERNEL" "Load        $CPU_LOAD"
printf '  %-54s  %s\n' "Hostname    $HOSTNAME" "Effort      ${CPU_EFFORT:-Unavailable}"
printf '  %-54s  %s\n' "Uptime      $UPTIME" 'Temperature Unavailable'
printf '\n'
printf '%-56s%s\n' 'Memory' 'Storage'
printf '  %-54s  %s\n' "Total       $(format_size "$TOTAL_MEMORY_KIB")" "Device      $DISK_NAME"
printf '  %-54s  %s\n' "Available   ${AVAILABLE_MEMORY:-unknown}" "Filesystem  ${FILESYSTEM:-unknown}"
printf '  %-54s  %s\n' "Used        ${USED_MEMORY:-unknown}" "Total       $(format_size "$DISK_TOTAL_KIB")"
printf '  %-54s  %s\n' '' "Free        $(format_size "$DISK_FREE_KIB")"
printf '  %-54s  %s\n' '' "Occupied    $(format_size "$DISK_USED_KIB")"
printf '\n'
printf 'Battery\n'

BATTERY_OUTPUT="$(pmset -g batt 2>/dev/null || true)"
CHARGE="$(printf '%s\n' "$BATTERY_OUTPUT" | grep -Eo '[0-9]+%' | head -n1 || true)"
if [[ -n "$CHARGE" ]]; then
  STATUS="$(printf '%s\n' "$BATTERY_OUTPUT" \
    | awk -F';' '/[0-9]+%/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
  POWER_INFO="$(system_profiler SPPowerDataType 2>/dev/null || true)"
  CYCLES="$(printf '%s\n' "$POWER_INFO" \
    | awk -F: '/Cycle Count/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
  MAX_CAPACITY="$(printf '%s\n' "$POWER_INFO" \
    | awk -F: '/Maximum Capacity/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
  CONDITION="$(printf '%s\n' "$POWER_INFO" \
    | awk -F: '/Condition/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

  HEALTH="${MAX_CAPACITY:-Unavailable}"
  if [[ -n "$CONDITION" && "$HEALTH" != 'Unavailable' ]]; then
    HEALTH="$HEALTH ($CONDITION)"
  elif [[ -n "$CONDITION" ]]; then
    HEALTH="$CONDITION"
  fi

  printf '  Charge      %s\n' "$CHARGE"
  printf '  Status      %s\n' "${STATUS:-unknown}"
  printf '  Cycle count %s\n' "${CYCLES:-Unavailable}"
  printf '  Health      %s\n' "$HEALTH"
else
  printf '  No battery (desktop or not available).\n'
fi
printf '\n'
