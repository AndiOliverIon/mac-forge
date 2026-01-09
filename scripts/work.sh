\
#!/usr/bin/env bash
set -euo pipefail

# work.sh - environment/work-state wizard + inspector
#
# Usage:
#   ./work.sh                # run wizard (fzf)
#   ./work.sh --info         # print current work-state.json in a friendly format
#   ./work.sh -i             # same as --info
#   ./work.sh info           # same as --info

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/configs"
STATE_FILE="${CONFIG_DIR}/work-state.json"

die() { echo "✗ $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

ensure_state_file_exists() {
  mkdir -p "${CONFIG_DIR}"
  if [[ ! -f "${STATE_FILE}" ]]; then
    cat > "${STATE_FILE}" <<'JSON'
{
  "storage": "offline",
  "container": "internal",
  "updated_at": ""
}
JSON
  fi
}

# Minimal JSON getter without jq (but prefers jq if available)
json_get() {
  local key="$1"
  local file="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$file"
  else
    python3 - "$key" "$file" <<'PY'
import json, sys
key, path = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)
v = obj.get(key, "")
if v is None:
    v = ""
print(v)
PY
  fi
}

pretty_storage() {
  case "$1" in
    external) echo "External storage connected (Hades)" ;;
    network)  echo "Network SQL backups available" ;;
    offline)  echo "Offline (no network / no external)" ;;
    *)        echo "Unknown ($1)" ;;
  esac
}

pretty_container() {
  case "$1" in
    external) echo "Externalized SQL data (bind-mount host path)" ;;
    internal) echo "Internal SQL data (Docker named volume)" ;;
    *)        echo "Unknown ($1)" ;;
  esac
}

show_info() {
  ensure_state_file_exists

  local storage container updated
  storage="$(json_get storage "${STATE_FILE}")"
  container="$(json_get container "${STATE_FILE}")"
  updated="$(json_get updated_at "${STATE_FILE}")"

  [[ -n "${storage}" ]] || storage="(not set)"
  [[ -n "${container}" ]] || container="(not set)"
  [[ -n "${updated}" ]] || updated="(not set)"

  echo "┌──────────────────────────────────────────────"
  echo "│ Work state"
  echo "├──────────────────────────────────────────────"
  echo "│ File      : ${STATE_FILE}"
  echo "│ Storage   : ${storage} — $(pretty_storage "${storage}")"
  echo "│ Container : ${container} — $(pretty_container "${container}")"
  echo "│ Updated   : ${updated}"
  echo "└──────────────────────────────────────────────"
}

write_state() {
  local storage="$1"
  local container="$2"
  local now
  now="$(date -Is 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S%z")"

  mkdir -p "${CONFIG_DIR}"
  ensure_state_file_exists

  if command -v jq >/dev/null 2>&1; then
    # Preserve all existing keys; only update the three we manage.
    jq --arg storage "$storage" \
       --arg container "$container" \
       --arg updated_at "$now" \
       '.storage=$storage | .container=$container | .updated_at=$updated_at' \
       "${STATE_FILE}" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  else
    # Python fallback: preserve existing JSON, only update those keys.
    python3 - "$STATE_FILE" "$storage" "$container" "$now" <<'PY'
import json, sys
path, storage, container, updated = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)
if not isinstance(obj, dict):
    obj = {}
obj["storage"] = storage
obj["container"] = container
obj["updated_at"] = updated
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2, ensure_ascii=False)
    f.write("\n")
import os
os.replace(tmp, path)
PY
  fi

  echo "✓ Saved: ${STATE_FILE}"
}


wizard() {
  need_cmd fzf
  ensure_state_file_exists

  local choiceA storage
  choiceA="$(
    printf "%s\n" \
      "external  External storage is connected to Hades" \
      "network   SQL storage for backups is available on network" \
      "offline   Neither network nor external storage is available" \
    | fzf --prompt="Select work storage scenario > " --with-nth=1,2 --delimiter='  ' --height=40% --border
  )" || exit 1
  storage="$(awk '{print $1}' <<<"${choiceA}")"

  local choiceB container
  choiceB="$(
    printf "%s\n" \
      "external  Externalized container (SQL data bind-mounted from host path)" \
      "internal  Internal container (SQL data stored in Docker named volume)" \
    | fzf --prompt="Select SQL container mode > " --with-nth=1,2 --delimiter='  ' --height=40% --border
  )" || exit 1
  container="$(awk '{print $1}' <<<"${choiceB}")"

  write_state "${storage}" "${container}"
  echo
  show_info
}

usage() {
  cat <<'HELP'
Usage:
  work.sh            Run the wizard (fzf) and save configs/work-state.json
  work.sh --info     Print current work state (friendly)
  work.sh -i         Same as --info
  work.sh info       Same as --info
HELP
}

main() {
  # More robust arg parsing: treat *any* of these tokens as info mode.
  local mode="wizard"
  for arg in "$@"; do
    case "$arg" in
      --info|-i|info) mode="info" ;;
      --help|-h|help) mode="help" ;;
    esac
  done

  case "$mode" in
    info) show_info ;;
    help) usage ;;
    wizard) wizard ;;
    *) die "Unknown mode" ;;
  esac
}

main "$@"
