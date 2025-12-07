#!/usr/bin/env bash
set -euo pipefail

echo "=== CPU & RAM (snapshot) ==="
TOP_OUTPUT="$(top -l 1 -n 0)"
echo "$TOP_OUTPUT" | awk '/CPU usage/ {print}'
echo "$TOP_OUTPUT" | awk '/PhysMem/ {print}'
echo

echo "=== Disk usage ==="
df -h / | awk 'NR==1 || NR==2'
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
