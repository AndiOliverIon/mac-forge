#!/usr/bin/env bash
set -euo pipefail

if pgrep openconnect >/dev/null 2>&1; then
	echo "VPN connected."
else
	echo "VPN not connected."
fi
