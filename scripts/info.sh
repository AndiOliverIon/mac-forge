#!/usr/bin/env bash
set -euo pipefail

echo "=== CPU & RAM (snapshot) ==="
TOP_OUTPUT="$(top -l 1 -n 0)"
echo "$TOP_OUTPUT" | awk '/CPU usage/ {print}'
echo "$TOP_OUTPUT" | awk '/PhysMem/ {print}'
echo

echo "=== Disk usage ==="
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

read -r DISK_NAME DISK_TOTAL_KIB DISK_USED_KIB DISK_FREE_KIB _ < <(df -k / | awk 'NR==2 {print $1, $2, $3, $4, $5}')
echo "Disk name: $DISK_NAME"
echo "Total: $(format_size "$DISK_TOTAL_KIB")"
echo "Free: $(format_size "$DISK_FREE_KIB")"
echo "Occupied: $(format_size "$DISK_USED_KIB")"
echo

echo "=== Battery ==="
if pmset -g batt &>/dev/null; then
  PCT=$(pmset -g batt | grep -Eo '[0-9]+%' | head -n1)
  CYCLES=$(system_profiler SPPowerDataType 2>/dev/null \
    | awk -F: '/Cycle Count/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
  echo "Charge: ${PCT:-unknown}"
  echo "Cycle count: ${CYCLES:-unknown}"
else
  echo "No battery (desktop or not available)."
fi
