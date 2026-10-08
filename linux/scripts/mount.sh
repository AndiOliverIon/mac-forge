#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
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

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/smb-credentials.sh"

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
        (
          if ((.credentials.chapter // "") != "" and (.credentials.remote // "") != "")
          then "\(.credentials.chapter)/\(.credentials.remote)"
          else "-"
          end
        ),
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

IFS=$'\t' read -r title protocol source mountpoint_raw credentials_ref extra_options <<< "$selected"
credentials_chapter=""
credentials_remote=""
if [[ -n "$credentials_ref" && "$credentials_ref" != "-" ]]; then
  credentials_chapter="${credentials_ref%%/*}"
  credentials_remote="${credentials_ref#*/}"
fi
[[ "$extra_options" == "-" ]] && extra_options=""

mountpoint="$(expand_home "$mountpoint_raw")"

[[ "$mountpoint" == /* ]] || die "Mountpoint must resolve to an absolute path: $mountpoint"

if is_mounted "$mountpoint"; then
  echo "Already mounted: [$title] $mountpoint"
  exit 0
fi

credentials_file=""
if [[ -n "$credentials_chapter" && -n "$credentials_remote" ]]; then
  credentials_file="$(forge_smb_materialize_credentials "$credentials_chapter" "$credentials_remote")"
  trap 'rm -f -- "$credentials_file"' EXIT
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
