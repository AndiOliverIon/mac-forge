#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/forge.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

expand_home() {
  local path="$1"

  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#"~/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

is_mounted() {
  local mountpoint="$1"

  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$mountpoint"
  else
    findmnt -rn --target "$mountpoint" >/dev/null 2>&1
  fi
}

require_cmd fzf
require_cmd jq
require_cmd mount
require_cmd mount.cifs
require_cmd sudo
require_cmd timeout

mount_rows="$(
  jq -r '
    .mounts // []
    | .[]
    | select(.title and .protocol and .source and .mountpoint)
    | [
        .title,
        .protocol,
        .source,
        .mountpoint,
        (.credentials_file // "-"),
        (.options // "-")
      ]
    | @tsv
  ' "$FORGE_RUNTIME_CONFIG_FILE"
)"

[[ -n "${mount_rows//$'\n'/}" ]] \
  || die "No mounts are configured in $FORGE_RUNTIME_CONFIG_FILE."

selected="$(
  printf '%s\n' "$mount_rows" \
    | fzf \
        --prompt='Mount > ' \
        --delimiter=$'\t' \
        --with-nth=1,3,4 \
        --height=50% \
        --reverse
)" || die "No mount selected."

IFS=$'\t' read -r title protocol source mountpoint_raw credentials_raw extra_options <<< "$selected"
[[ "$credentials_raw" == "-" ]] && credentials_raw=""
[[ "$extra_options" == "-" ]] && extra_options=""

mountpoint="$(expand_home "$mountpoint_raw")"
credentials_file=""
if [[ -n "$credentials_raw" ]]; then
  credentials_file="$(expand_home "$credentials_raw")"
  [[ -f "$credentials_file" ]] \
    || die "Credentials file not found: $credentials_file"
fi

[[ "$mountpoint" == /* ]] || die "Mountpoint must resolve to an absolute path: $mountpoint"

if is_mounted "$mountpoint"; then
  echo "Already mounted: [$title] $mountpoint"
  exit 0
fi

if [[ ! -d "$mountpoint" ]]; then
  sudo mkdir -p -- "$mountpoint"
fi

case "$protocol" in
  smb)
    options="uid=$(id -u),gid=$(id -g)"
    [[ -z "$credentials_file" ]] || options+=",credentials=$credentials_file"
    [[ -z "$extra_options" ]] || options+=",$extra_options"

    echo "Mounting [$title]"
    echo "  Source     : $source"
    echo "  Mountpoint : $mountpoint"

    timeout --foreground 30s \
      sudo mount -t cifs "$source" "$mountpoint" -o "$options" \
      || die "Failed to mount [$title]."
    ;;
  *)
    die "Unsupported mount protocol: $protocol"
    ;;
esac

is_mounted "$mountpoint" || die "Mount command completed but $mountpoint is not mounted."
echo "Mounted: [$title] $mountpoint"
