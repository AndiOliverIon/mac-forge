#!/usr/bin/env bash

# Map a remote SQL backup path to the local directory on its SMB share.

backup_share_host() {
  local source="$1"
  source="${source#smb://}"
  source="${source#//}"
  printf '%s\n' "${source%%/*}"
}

backup_share_name() {
  local source="$1"
  source="${source#smb://}"
  source="${source#//}"
  python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]), end="")' "${source#*/}"
}

backup_path_segments() {
  local path="$1"
  local part
  path="${path//\\//}"
  local IFS='/'
  for part in $path; do
    [[ -z "$part" || "$part" == *: ]] && continue
    printf '%s\n' "$part"
  done
}

find_mounted_share() {
  local host="$1"
  local share="$2"
  python3 - "$host" "$share" <<'PY'
import subprocess
import sys
import urllib.parse

host = sys.argv[1].casefold()
share = sys.argv[2].casefold()
mounts = subprocess.check_output(["mount"], text=True, errors="replace")
for line in mounts.splitlines():
    if " on " not in line or " (" not in line:
        continue
    source, rest = line.split(" on ", 1)
    mountpoint = rest.rsplit(" (", 1)[0]
    decoded = urllib.parse.unquote(source).casefold()
    if host in decoded and f"/{share}" in decoded:
        print(mountpoint)
        break
PY
}

resolve_backup_scan_dir() {
  local mountpoint="$1"
  local share="$2"
  local backuppath="$3"
  local -a segments=()
  local segment candidate start i

  while IFS= read -r segment; do
    [[ -n "$segment" ]] && segments+=("$segment")
  done < <(backup_path_segments "$backuppath")

  local n="${#segments[@]}"
  for ((start = 0; start < n; start++)); do
    candidate="$mountpoint"
    for ((i = start; i < n; i++)); do
      candidate+="/${segments[i]}"
    done
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  local last="${segments[n - 1]:-}"
  if [[ -n "$share" && -d "$mountpoint" && "${last,,}" == "${share,,}" ]]; then
    printf '%s\n' "$mountpoint"
    return 0
  fi

  return 1
}
