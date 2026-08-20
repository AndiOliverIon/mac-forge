#!/usr/bin/env bash
set -euo pipefail

echo "Suspending MasterChief..."

exec ssh -t oliver@masterchief "sudo systemctl suspend"
