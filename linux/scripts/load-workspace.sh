#!/usr/bin/env bash
# Script to load a test workspace layout.
# Step 1: Clear current workspace
# Step 2: Load tabbed layout
# Step 3: Launch Rider, Code, and 4 Terminals in a 2x2 grid

FORGE_LINUX_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAYOUT_FILE="${FORGE_LINUX_ROOT}/config/work-layout.json"

echo "Step 1: Closing all windows on current workspace..."
# We use [workspace=__current__] to target the active workspace
i3-msg "[workspace=__current__] kill"

# Small delay to ensure windows are closed
sleep 1

echo "Step 2: Loading layout..."
i3-msg "append_layout ${LAYOUT_FILE}"

echo "Step 3: Launching apps..."
# IDEs
i3-msg exec "rider"
i3-msg exec "code"

# 4 Terminals for the 2x2 grid
# Using --class sets the instance name (WM_CLASS) for matching in i3
i3-msg exec "gnome-terminal --class=Forge-TL"
i3-msg exec "gnome-terminal --class=Forge-TR"
i3-msg exec "gnome-terminal --class=Forge-BL"
i3-msg exec "gnome-terminal --class=Forge-BR"

echo "Done. IDEs are in the first tab (stacked), and a 2x2 terminal grid is in the second tab."
