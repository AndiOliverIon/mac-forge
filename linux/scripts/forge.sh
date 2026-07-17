#!/usr/bin/env bash
set -euo pipefail

FORGE_LINUX_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_LINUX_ROOT="$(cd -- "${FORGE_LINUX_SCRIPT_DIR}/.." && pwd)"
FORGE_HOME_ROOT="${FORGE_HOME_ROOT:-/data/forge}"
FORGE_RUNTIME_CONFIG_FILE="${FORGE_LINUX_ROOT}/config/runtime.json"
FORGE_SECRETS_FILE="${FORGE_HOME_ROOT}/forge-secrets.sh"

if [[ -f "$FORGE_SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$FORGE_SECRETS_FILE"
fi

forge_die() {
  echo "ERROR: $*" >&2
  exit 1
}

forge_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || forge_die "Required command '$1' not found."
}

forge_require_docker_access() {
  forge_require_cmd docker

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if getent group docker | awk -F: -v user="$USER" '
    {
      count = split($4, members, ",")
      for (i = 1; i <= count; i++) {
        if (members[i] == user) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  '; then
    forge_die "Docker access is not active in this login session. Sign out of Ubuntu completely, sign back in, then run 'docker ps'."
  fi

  forge_die "Docker access is unavailable. Add ${USER} to the docker group, then sign out and back in."
}

forge_prepare_sql_shared_path() {
  local path="$1"

  forge_require_cmd setfacl
  mkdir -p "$path"

  setfacl -m "u:${USER}:rwx,u:10001:rwx" "$path"
  setfacl -d -m "u:${USER}:rwx,u:10001:rwx" "$path"
}

forge__json_get() {
  local key_path="$1"
  local mode="${2:-text}"

  python3 - "$FORGE_RUNTIME_CONFIG_FILE" "$key_path" "$mode" <<'PY'
import json
import sys

runtime_file, key_path, mode = sys.argv[1:4]

with open(runtime_file, "r", encoding="utf-8") as handle:
    data = json.load(handle)

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

  if [[ "$key_path" == "sql.sa_password" ]]; then
    [[ -n "${FORGE_SQL_SA_PASSWORD:-}" ]] || forge_die "Missing secret: FORGE_SQL_SA_PASSWORD"
    printf '%s\n' "$FORGE_SQL_SA_PASSWORD"
    return 0
  fi

  forge__json_get "$key_path" text || forge_die "Missing config key: $key_path"
}

forge_get_optional() {
  local key_path="$1"

  if [[ "$key_path" == "sql.sa_password" ]]; then
    printf '%s\n' "${FORGE_SQL_SA_PASSWORD:-}"
    return 0
  fi

  forge__json_get "$key_path" text 2>/dev/null || true
}

forge_get_json() {
  local key_path="$1"
  forge__json_get "$key_path" json || forge_die "Missing config key: $key_path"
}

forge_get_json_optional() {
  local key_path="$1"
  forge__json_get "$key_path" json 2>/dev/null || true
}

forge_resolve_path() {
  local value="$1"
  local base_path="${2:-$FORGE_LINUX_ROOT}"

  if [[ "$value" == /* ]]; then
    printf '%s\n' "$value"
  elif [[ "$base_path" == /* ]]; then
    printf '%s\n' "${base_path}/${value}"
  else
    printf '%s\n' "${FORGE_LINUX_ROOT}/${base_path}/${value}"
  fi
}

forge_get_path() {
  local key_path="$1"
  local value
  value="$(forge_get "$key_path")"

  forge_resolve_path "$value"
}

forge_get_path_from_root() {
  local key_path="$1"
  local root_key_path="$2"
  local value root_value

  value="$(forge_get "$key_path")"
  root_value="$(forge_get_optional "$root_key_path")"

  if [[ -n "$root_value" ]]; then
    forge_resolve_path "$value" "$root_value"
    return 0
  fi

  forge_resolve_path "$value"
}

forge_assert_sensitive_config() {
  [[ -f "$FORGE_SECRETS_FILE" ]] || forge_die "Missing sensitive config: $FORGE_SECRETS_FILE"
  [[ -n "${FORGE_SQL_SA_PASSWORD:-}" ]] || forge_die "FORGE_SQL_SA_PASSWORD is missing from $FORGE_SECRETS_FILE"
}

export \
  FORGE_LINUX_SCRIPT_DIR \
  FORGE_LINUX_ROOT \
  FORGE_HOME_ROOT \
  FORGE_RUNTIME_CONFIG_FILE \
  FORGE_SECRETS_FILE
