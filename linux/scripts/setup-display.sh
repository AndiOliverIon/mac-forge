#!/bin/bash

# Arguments handling:
# 1. No arguments: Both set to 110%
# 2. One argument: Both set to that value
# 3. Two arguments: Primary (DP-4) set to $1, Secondary (DP-2) set to $2

PRIMARY_ZOOM=${1:-100}
SECONDARY_ZOOM=${2:-$PRIMARY_ZOOM}

# Function to convert zoom percentage to xrandr scale factor
# xrandr_scale = 100 / zoom_percent
# (e.g., 125% zoom = 100/125 = 0.8x0.8 scale)
get_scale() {
    local zoom=$1
    # Check if zoom is a valid number
    if [[ ! "$zoom" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Zoom value '$zoom' must be a number." >&2
        exit 1
    fi
    # Use awk for floating point division to get 3 decimal places
    awk "BEGIN {printf \"%.3fx%.3f\", 100/$zoom, 100/$zoom}"
}

PRIMARY_SCALE=$(get_scale $PRIMARY_ZOOM)
SECONDARY_SCALE=$(get_scale $SECONDARY_ZOOM)

echo "Setting Primary (DP-4) to ${PRIMARY_ZOOM}% ($PRIMARY_SCALE)"
echo "Setting Secondary (DP-2) to ${SECONDARY_ZOOM}% ($SECONDARY_SCALE)"

xrandr --output DP-4 --primary --auto --scale "$PRIMARY_SCALE" --output DP-2 --auto --scale "$SECONDARY_SCALE" --right-of DP-4
