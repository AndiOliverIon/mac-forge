#!/usr/bin/env bash

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  hades-umount.sh [--mountpoint PATH] [--lazy]
EOF
}

MOUNTPOINT="${FORGE_HADES_MOUNTPOINT:-$HOME/hades}"
UMOUNT_OPTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mountpoint)
      shift
      [[ $# -gt 0 ]] || die "--mountpoint requires a value."
      MOUNTPOINT="$1"
      ;;
    --lazy)
      UMOUNT_OPTS+=("-l")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

if ! findmnt -rn --target "$MOUNTPOINT" >/dev/null 2>&1; then
  echo "Not mounted: $MOUNTPOINT"
  exit 0
fi

sudo umount "${UMOUNT_OPTS[@]}" "$MOUNTPOINT"
echo "Unmounted: $MOUNTPOINT"
