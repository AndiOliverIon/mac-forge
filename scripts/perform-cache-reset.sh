#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [path]

Behavior:
  - If [path] is provided, it may point to either the solution root or directly to ardis.perform.client.
  - If no path is provided, the script walks upward from the current directory and picks the nearest ardis.perform.client.
  - Removes Angular/Vite cache folders for the resolved client.
EOF
}

resolve_client_dir() {
  local input_path="${1:-}"
  local current=""

  if [[ -n "$input_path" ]]; then
    current="$(cd "$input_path" 2>/dev/null && pwd)" || die "Path not found: $input_path"
  else
    current="$PWD"
  fi

  while [[ "$current" != "/" ]]; do
    if [[ "$(basename "$current")" == "ardis.perform.client" ]]; then
      printf '%s\n' "$current"
      return 0
    fi

    if [[ -d "$current/ardis.perform.client" ]]; then
      printf '%s\n' "$current/ardis.perform.client"
      return 0
    fi

    current="$(dirname "$current")"
  done

  return 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

CLIENT_DIR="$(resolve_client_dir "${1:-}")" || die "Could not find ardis.perform.client from: ${1:-$PWD}"

CACHE_PATHS=(
  "$CLIENT_DIR/.angular/cache"
  "$CLIENT_DIR/node_modules/.vite"
)

echo "Client: $CLIENT_DIR"

removed_any=0
for cache_path in "${CACHE_PATHS[@]}"; do
  if [[ -e "$cache_path" ]]; then
    rm -rf "$cache_path"
    echo "Removed: $cache_path"
    removed_any=1
  else
    echo "Missing:  $cache_path"
  fi
done

if [[ "$removed_any" -eq 0 ]]; then
  echo "Nothing to clear."
fi
