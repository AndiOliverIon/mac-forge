#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_CONFIG_FILE="${FORGE_ROOT}/linux/config/runtime.json"

die() { echo "✖ $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS mount helper. On Linux, run linux/scripts/mount.sh."
[[ -f "$RUNTIME_CONFIG_FILE" ]] || die "Missing runtime config: $RUNTIME_CONFIG_FILE"

require_cmd jq
require_cmd fzf
require_cmd open
require_cmd python3
require_cmd mount_smbfs

# shellcheck disable=SC1091
source "${FORGE_ROOT}/linux/scripts/smb-credentials.sh"

expand_home() {
  local path="$1"

  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#"~/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

requested_id="${1:-}"

mount_rows="$(
  jq -r --arg id "$requested_id" '
    .mounts // []
    | .[]
    | select(.id and .title and .macos.source)
    | select($id == "" or .id == $id)
    | [
        .id,
        .title,
        .macos.source,
        (.credentials.chapter // ""),
        (.credentials.remote // ""),
        (.macos.mountpoint // "")
      ]
    | @tsv
  ' "$RUNTIME_CONFIG_FILE"
)"

[[ -n "${mount_rows//$'\n'/}" ]] || die "No macOS mount named '${requested_id:-*}' in $RUNTIME_CONFIG_FILE."

if [[ -n "$requested_id" ]]; then
  selected="$mount_rows"
  [[ "$selected" != *$'\n'* ]] || die "Multiple macOS mounts matched '$requested_id'."
else
  selected="$(
    printf '%s\n' "$mount_rows" |
      fzf --prompt='Mount > ' --delimiter=$'\t' --with-nth=2,3 --height=50% --reverse
  )" || die "No mount selected."
fi

IFS=$'\t' read -r mount_id title smb_url credentials_chapter credentials_remote mountpoint_raw <<< "$selected"
[[ "$smb_url" == smb://* ]] || die "Mount '$mount_id' has an invalid macOS source: $smb_url"

echo "Connecting [$title]"
echo "  Source: $smb_url"

if [[ -z "$credentials_chapter" || -z "$credentials_remote" ]]; then
  open "$smb_url"
  exit 0
fi

[[ -n "$mountpoint_raw" ]] || die "Mount '$mount_id' has credentials but no macos.mountpoint."
mountpoint="$(expand_home "$mountpoint_raw")"
mkdir -p -- "$mountpoint"

echo "  Credentials: ${credentials_chapter}/${credentials_remote}"
echo "  Mountpoint: $mountpoint"

credentials_file="$(forge_smb_materialize_credentials "$credentials_chapter" "$credentials_remote")"
trap 'rm -f -- "$credentials_file"' EXIT

python3 - "$credentials_file" "$smb_url" "$mountpoint" <<'PY'
import re
import subprocess
import sys
import urllib.parse

credentials_file, smb_url, mountpoint = sys.argv[1:4]
username = ""
password = ""
with open(credentials_file, encoding="utf-8") as handle:
    for line in handle:
        if line.startswith("username="):
            username = line.split("=", 1)[1].rstrip("\n")
        elif line.startswith("password="):
            password = line.split("=", 1)[1].rstrip("\n")

parsed = urllib.parse.urlparse(smb_url)
share = urllib.parse.unquote(parsed.path.lstrip("/"))
if not parsed.hostname or not share:
    print("SMB URL is missing a server or share.", file=sys.stderr)
    sys.exit(1)

domain = ""
user = username
if "\\" in username:
    domain, user = username.split("\\", 1)

auth = urllib.parse.quote(user, safe="")
if domain:
    auth = urllib.parse.quote(domain, safe="") + ";" + auth
auth += ":" + urllib.parse.quote(password, safe="")
target = f"//{auth}@{parsed.hostname}/{urllib.parse.quote(share, safe='/')}"

result = subprocess.run(
    ["/sbin/mount_smbfs", target, mountpoint],
    text=True,
    capture_output=True,
)
output = (result.stdout or "") + (result.stderr or "")
output = re.sub(r"//\S+", "//<redacted>", output)
if password:
    output = output.replace(password, "***")
if output.strip():
    print(output.rstrip(), file=sys.stderr)
sys.exit(result.returncode)
PY

if mount | grep -F " on ${mountpoint} (" >/dev/null; then
  echo "Mounted: [$title] $mountpoint"
else
  die "Mount command finished but $mountpoint is not mounted."
fi
