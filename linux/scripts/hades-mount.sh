#!/usr/bin/env bash

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }
run_with_timeout() {
  local seconds="$1"
  shift

  require_cmd timeout
  if ! timeout --foreground "${seconds}s" "$@"; then
    die "Mount timed out after ${seconds}s."
  fi
}
is_mounted() {
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$1"
    return
  fi

  if command -v findmnt >/dev/null 2>&1; then
    findmnt -rn --target "$1" >/dev/null 2>&1
    return
  fi

  grep -Fqs " $1 " /proc/mounts
}

usage() {
  cat <<'EOF'
Usage:
  hades-mount.sh [--smb|--nfs]
                 [--host HOST] [--user USER] [--mountpoint PATH]
                 [--share SHARE] [--export PATH]
                 [--smb-options OPTS] [--nfs-options OPTS]

Examples:
  hades-mount.sh
  hades-mount.sh --nfs
  hades-mount.sh --share shared
EOF
}

HOST="${FORGE_HADES_HOST:-hadesw}"
USER_NAME="${FORGE_HADES_USER:-oliver}"
MOUNTPOINT="${FORGE_HADES_MOUNTPOINT:-$HOME/hades}"
PROTOCOL="${FORGE_HADES_PROTOCOL:-smb}"
SMB_SHARE="${FORGE_HADES_SMB_SHARE:-shared}"
DEFAULT_SMB_OPTS="username=${USER_NAME},uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755,vers=3.0,mfsymlinks"
if [[ -f "${HOME}/.smbcredentials" ]]; then
  DEFAULT_SMB_OPTS="credentials=${HOME}/.smbcredentials,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755,vers=3.0,mfsymlinks"
fi
SMB_OPTS="${FORGE_HADES_SMB_OPTS:-$DEFAULT_SMB_OPTS}"
NFS_EXPORT="${FORGE_HADES_NFS_EXPORT:-/Users/oliver}"
NFS_OPTS="${FORGE_HADES_NFS_OPTS:-defaults}"
MOUNT_TIMEOUT_SECS="${FORGE_HADES_MOUNT_TIMEOUT_SECS:-15}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smb)
      PROTOCOL="smb"
      ;;
    --nfs)
      PROTOCOL="nfs"
      ;;
    --host)
      shift
      [[ $# -gt 0 ]] || die "--host requires a value."
      HOST="$1"
      ;;
    --user)
      shift
      [[ $# -gt 0 ]] || die "--user requires a value."
      USER_NAME="$1"
      ;;
    --mountpoint)
      shift
      [[ $# -gt 0 ]] || die "--mountpoint requires a value."
      MOUNTPOINT="$1"
      ;;
    --share)
      shift
      [[ $# -gt 0 ]] || die "--share requires a value."
      SMB_SHARE="$1"
      ;;
    --export)
      shift
      [[ $# -gt 0 ]] || die "--export requires a value."
      NFS_EXPORT="$1"
      ;;
    --smb-options)
      shift
      [[ $# -gt 0 ]] || die "--smb-options requires a value."
      SMB_OPTS="$1"
      ;;
    --nfs-options)
      shift
      [[ $# -gt 0 ]] || die "--nfs-options requires a value."
      NFS_OPTS="$1"
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

mkdir -p "$MOUNTPOINT"

if is_mounted "$MOUNTPOINT"; then
  echo "$MOUNTPOINT is already mounted."
  exit 0
fi

case "$PROTOCOL" in
  smb)
    require_cmd sudo
    require_cmd mount
    require_cmd mount.cifs
    echo "Mounting SMB //${HOST}/${SMB_SHARE} to ${MOUNTPOINT}"
    run_with_timeout "$MOUNT_TIMEOUT_SECS" sudo mount -t cifs "//${HOST}/${SMB_SHARE}" "$MOUNTPOINT" -o "$SMB_OPTS"
    ;;
  nfs)
    require_cmd sudo
    require_cmd mount
    require_cmd mount.nfs
    echo "Mounting NFS ${HOST}:${NFS_EXPORT} to ${MOUNTPOINT}"
    run_with_timeout "$MOUNT_TIMEOUT_SECS" sudo mount -t nfs -o "$NFS_OPTS" "${HOST}:${NFS_EXPORT}" "$MOUNTPOINT"
    ;;
  *)
    die "Unsupported protocol: $PROTOCOL"
    ;;
esac

echo "Mounted ${MOUNTPOINT}"
