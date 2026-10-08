#!/usr/bin/env bash

# Map a remote SQL backup path to the local directory on its SMB share.

backup_share_host() {
  local source="$1"
  source="${source#smb://}"
  source="${source#//}"
  source="${source%%/*}"
  source="${source##*@}"
  printf '%s\n' "$source"
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
  while [[ "$path" == */* ]]; do
    part="${path%%/*}"
    path="${path#*/}"
    [[ -z "$part" || "$part" == *: ]] && continue
    printf '%s\n' "$part"
  done
  [[ -z "$path" || "$path" == *: ]] && return 0
  printf '%s\n' "$path"
}

# kind=mac prints id and source. kind=linux prints source, mountpoint, chapter, remote, options.
runtime_mount_rows() {
  local host="$1"
  local kind="$2"
  jq -r --arg host "$host" --arg kind "$kind" '
    def smb_host:
      sub("^smb://"; "")
      | sub("^//"; "")
      | split("/")[0]
      | sub(".*@"; "")
      | ascii_downcase;
    .mounts // []
    | .[]
    | select(.source != null)
    | select((.source | smb_host) == ($host | ascii_downcase))
    | if $kind == "linux" then
        select(.mountpoint != null and .credentials.chapter != null and .credentials.remote != null)
        | [.source, .mountpoint, .credentials.chapter, .credentials.remote, (.options // "")]
      else
        select(.id != null)
        | [.id, .source]
      end
    | @tsv
  ' "$RUNTIME_CONFIG_FILE"
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

def parsed_source(source):
    decoded = urllib.parse.unquote(source).strip()
    folded = decoded.casefold()
    if folded.startswith("smb://"):
        decoded = decoded[6:]
    elif decoded.startswith("//"):
        decoded = decoded[2:]
    authority, separator, path = decoded.partition("/")
    if "@" in authority:
        authority = authority.rsplit("@", 1)[1]
    share_name = path.split("/", 1)[0] if separator else ""
    return authority.casefold(), share_name.casefold()

mounts = subprocess.check_output(["mount"], text=True, errors="replace")
for line in mounts.splitlines():
    if " on " not in line or " (" not in line:
        continue
    source, rest = line.split(" on ", 1)
    mountpoint = rest.rsplit(" (", 1)[0]
    mounted_host, mounted_share = parsed_source(source)
    if mounted_host == host and mounted_share == share:
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
