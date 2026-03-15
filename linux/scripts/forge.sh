#!/usr/bin/env bash
set -euo pipefail

FORGE_LINUX_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_LINUX_ROOT="$(cd -- "${FORGE_LINUX_SCRIPT_DIR}/.." && pwd)"
FORGE_HOME_ROOT="${FORGE_HOME_ROOT:-$HOME/forge}"
FORGE_RUNTIME_CONFIG_FILE="${FORGE_LINUX_ROOT}/config/runtime.json"
FORGE_SENSITIVE_CONFIG_FILE="${FORGE_HOME_ROOT}/forge-secrets.json"

forge_die() {
  echo "ERROR: $*" >&2
  exit 1
}

forge_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || forge_die "Required command '$1' not found."
}

forge__json_get() {
  local key_path="$1"
  local mode="${2:-text}"

  python3 - "$FORGE_RUNTIME_CONFIG_FILE" "$FORGE_SENSITIVE_CONFIG_FILE" "$key_path" "$mode" <<'PY'
import json
import os
import sys

runtime_file, sensitive_file, key_path, mode = sys.argv[1:5]

def deep_merge(base, incoming):
    if isinstance(base, dict) and isinstance(incoming, dict):
        merged = dict(base)
        for key, value in incoming.items():
            if key in merged:
                merged[key] = deep_merge(merged[key], value)
            else:
                merged[key] = value
        return merged
    return incoming

data = {}
for path in (runtime_file, sensitive_file):
    if not os.path.exists(path):
        continue
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    data = deep_merge(data, payload)

value = data
for part in key_path.split("."):
    if not isinstance(value, dict) or part not in value:
        sys.exit(2)
    value = value[part]

if mode == "json":
    print(json.dumps(value, ensure_ascii=False))
elif isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

forge_get() {
  local key_path="$1"
  forge__json_get "$key_path" text || forge_die "Missing config key: $key_path"
}

forge_get_json() {
  local key_path="$1"
  forge__json_get "$key_path" json || forge_die "Missing config key: $key_path"
}

forge_get_path() {
  local key_path="$1"
  local value
  value="$(forge_get "$key_path")"

  if [[ "$value" == /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "${FORGE_LINUX_ROOT}/${value}"
  fi
}

forge_assert_sensitive_config() {
  [[ -f "$FORGE_SENSITIVE_CONFIG_FILE" ]] || forge_die "Missing sensitive config: $FORGE_SENSITIVE_CONFIG_FILE"
}

export \
  FORGE_LINUX_SCRIPT_DIR \
  FORGE_LINUX_ROOT \
  FORGE_HOME_ROOT \
  FORGE_RUNTIME_CONFIG_FILE \
  FORGE_SENSITIVE_CONFIG_FILE
