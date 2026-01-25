#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(pwd)"

echo "🔍 Searching for bin folders under:"
echo "   $ROOT_DIR"
echo

find "$ROOT_DIR" -type d -name bin | while read -r bin_dir; do
  if [ -d "$bin_dir" ]; then
    echo "🧹 Cleaning: $bin_dir"
    rm -rf "$bin_dir"/*
  fi
done

echo
echo "✅ Done. All bin folders cleaned."
