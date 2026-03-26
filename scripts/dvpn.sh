#!/usr/bin/env bash
set -euo pipefail

echo "Disconnecting VPN..."
if pgrep openconnect >/dev/null; then
    sudo pkill -SIGINT openconnect
    echo "VPN Disconnected."
else
    echo "No active VPN connection found."
fi
