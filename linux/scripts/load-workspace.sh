#!/usr/bin/env bash
# Script to load a test workspace layout on the primary monitor (DP-4).
# Step 1: Ensure we are on Workspace 1 on the Primary Monitor
# Step 2: Clear workspace
# Step 3: Load tabbed layout
# Step 4: Launch Rider, Code, and 4 Terminals in a 2x2 grid

FORGE_LINUX_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAYOUT_FILE="${FORGE_LINUX_ROOT}/config/work-layout.json"
PRIMARY_OUTPUT="DP-4"
TARGET_WORKSPACE="1"

echo "Step 1: Moving focus to ${PRIMARY_OUTPUT} and Workspace ${TARGET_WORKSPACE}..."
# This command ensures Workspace 1 is on DP-4 and that it's the active workspace.
# If it's on DP-2, it moves it to DP-4.
i3-msg "workspace ${TARGET_WORKSPACE}; move workspace to output ${PRIMARY_OUTPUT}; workspace ${TARGET_WORKSPACE}"

# Give i3 a moment to focus the workspace before killing anything.
sleep 0.5

echo "Step 2: Closing windows only on Workspace ${TARGET_WORKSPACE}..."
# Using [workspace=...] without quotes is safer for i3-msg parsing sometimes.
# It ensures only windows ON that workspace are targeted.
i3-msg "[workspace=\"${TARGET_WORKSPACE}\"] kill"

# Ensure workspace is clean and ready
sleep 1

echo "Step 3: Loading layout into Workspace ${TARGET_WORKSPACE}..."
i3-msg "workspace ${TARGET_WORKSPACE}; append_layout ${LAYOUT_FILE}"

echo "Step 4: Launching apps..."
# IDEs
i3-msg exec "rider"
i3-msg exec "code"

# 4 Terminals for the 2x2 grid
i3-msg exec "gnome-terminal --title=Forge-TL"
i3-msg exec "gnome-terminal --title=Forge-TR"
i3-msg exec "gnome-terminal --title=Forge-BL"
i3-msg exec "gnome-terminal --title=Forge-BR"

echo "Done. Layout loaded on Workspace ${TARGET_WORKSPACE} (${PRIMARY_OUTPUT})."
