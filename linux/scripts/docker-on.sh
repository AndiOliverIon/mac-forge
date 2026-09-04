#!/usr/bin/env bash

set -euo pipefail

if docker info >/dev/null 2>&1; then
    echo "Docker is already ready."
    exit 0
fi

echo "Starting Docker Engine..."
sudo systemctl start docker.service

for attempt in {1..30}; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready."
        exit 0
    fi

    sleep 1
done

echo "ERROR: Docker did not become ready within 30 seconds." >&2
exit 1
