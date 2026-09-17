#!/usr/bin/env bash
# forge.sh

#######################################
# Machine / repo
#######################################
FORGE_MACHINE_NAME="${FORGE_MACHINE_NAME:-Hades}"
FORGE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="${FORGE_ROOT:-$(cd -- "${FORGE_SCRIPT_DIR}/.." && pwd)}"

#######################################
# Config (work state)
#######################################
FORGE_CONFIG_DIR="${FORGE_ROOT}/configs"
FORGE_CONFIG_LOCAL_DIR="${FORGE_ROOT}/config-local"
FORGE_WORK_STATE_FILE="${FORGE_CONFIG_DIR}/work-state.json"

#######################################
# Storage roots (EDIT THESE ON DEMAND)
#
# You have 3 scenarios:
#   1) External storage connected (e.g. acasis)
#   2) Network storage available
#   3) Neither available (offline / internal only)
#######################################

# Local root (internal storage)
FORGE_SQL_LOCAL_ROOT="$HOME/sql" # e.g. /Users/oliver/sql

# External storage root (acasis). If the path doesn't exist, forge will try to auto-detect "/Volumes/**/acasis".
# Keep this as your preferred default once discovered.
FORGE_SQL_EXTERNAL_ROOT="${FORGE_SQL_EXTERNAL_ROOT:-/Volumes/acasis/sql}"

# Network storage root. Set this to your mounted network path.
FORGE_SQL_NETWORK_ROOT="${FORGE_SQL_NETWORK_ROOT:-/Volumes/sql-network/sql}"

#######################################
# Per-storage: snapshots + external container data roots
#
# Requirement:
# - For each of the 3 locations, keep 2 variables:
#   (1) where SQL docker DATA lives when container is "external" (bind mount)
#   (2) snapshots folder where you work (.bak files)
#######################################
FORGE_SQL_LOCAL_SNAPSHOTS_PATH="${FORGE_SQL_LOCAL_ROOT}/snapshots"
FORGE_SQL_LOCAL_DOCKER_DATA_PATH="${FORGE_SQL_LOCAL_ROOT}/docker-mssql"

FORGE_SQL_EXTERNAL_SNAPSHOTS_PATH="${FORGE_SQL_EXTERNAL_ROOT}/snapshots"
FORGE_SQL_EXTERNAL_DOCKER_DATA_PATH="${FORGE_SQL_EXTERNAL_ROOT}/docker-mssql"

FORGE_SQL_NETWORK_SNAPSHOTS_PATH="${FORGE_SQL_NETWORK_ROOT}/snapshots"
FORGE_SQL_NETWORK_DOCKER_DATA_PATH="${FORGE_SQL_NETWORK_ROOT}/docker-mssql"

#######################################
# SQL container paths
#######################################
FORGE_SQL_DOCKER_ROOT="/var/opt/mssql"
FORGE_SQL_DOCKER_SNAPSHOTS_PATH="${FORGE_SQL_DOCKER_ROOT}/snapshots"

#######################################
# iCloud forge folder (for private configs)
#######################################
FORGE_ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
FORGE_ICLOUD_FORGE_DIR="$FORGE_ICLOUD_ROOT/forge"
FORGE_SECRETS_FILE="${FORGE_SECRETS_FILE:-$FORGE_ICLOUD_FORGE_DIR/forge-secrets.sh}"

#######################################
# Docker / SQL Server
#######################################
FORGE_SQL_DOCKER_CONTAINER="forge-sql"
FORGE_SQL_USER="sa"
FORGE_SQL_PORT="${FORGE_SQL_PORT:-2022}"
FORGE_SQL_DOCKER_IMAGE="${FORGE_SQL_DOCKER_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"

# Internal container mode = SQL data lives in a named Docker volume
FORGE_SQL_DATA_VOLUME_NAME="${FORGE_SQL_DATA_VOLUME_NAME:-forge-sql-data}"

#######################################
# Work state (paths only)
#
# These are set based on configs/work-state.json:
#   docker-path           -> FORGE_SQL_DATA_BIND_PATH
#   docker-snapshot-path  -> FORGE_SQL_SNAPSHOTS_PATH
#
# Contract:
# - docker data is ALWAYS bind-mounted from FORGE_SQL_DATA_BIND_PATH
# - snapshots are ALWAYS bind-mounted from FORGE_SQL_SNAPSHOTS_PATH
#######################################

# Defaults (empty until work-state.json is set via work.sh)
FORGE_SQL_SNAPSHOTS_PATH="${FORGE_SQL_SNAPSHOTS_PATH:-}"
FORGE_SQL_DATA_MOUNT_KIND="bind"
FORGE_SQL_DATA_BIND_PATH="${FORGE_SQL_DATA_BIND_PATH:-}"

forge__read_work_state() {
  local f="$FORGE_WORK_STATE_FILE"
  [[ -f "$f" ]] || return 0

  # Use python3 to read JSON (avoid jq dependency).
  python3 - <<'PY' "$f" 2>/dev/null || true
import json, sys
p = sys.argv[1]
try:
  with open(p, "r", encoding="utf-8") as fp:
    j = json.load(fp)
  docker_path = (j.get("docker-path") or "").strip()
  snap_path = (j.get("docker-snapshot-path") or "").strip()
  browser = (j.get("browser") or "Brave Browser").strip()
  if docker_path:
    print("FORGE_SQL_DATA_BIND_PATH\t" + docker_path)
  if snap_path:
    print("FORGE_SQL_SNAPSHOTS_PATH\t" + snap_path)
  if browser:
    print("FORGE_BROWSER\t" + browser)
except Exception:
  pass
PY
}

forge__apply_work_state() {
  local parsed key value
  parsed="$(forge__read_work_state)"
  [[ -n "${parsed//$'\n'/}" ]] || return 0

  while IFS=$'\t' read -r key value; do
    case "$key" in
      FORGE_SQL_DATA_BIND_PATH)
        [[ -n "$value" ]] && FORGE_SQL_DATA_BIND_PATH="$value"
        ;;
      FORGE_SQL_SNAPSHOTS_PATH)
        [[ -n "$value" ]] && FORGE_SQL_SNAPSHOTS_PATH="$value"
        ;;
      FORGE_BROWSER)
        [[ -n "$value" ]] && FORGE_BROWSER="$value"
        ;;
    esac
  done <<< "$parsed"

  # Enforce mount kind for this workflow.
  FORGE_SQL_DATA_MOUNT_KIND="bind"
}

# Apply the state immediately on source so every script gets consistent vars.
forge__apply_work_state

# Snapshot defaults after work-state so --version can retarget without losing
# the no-arg forge-sql / 2022 flow.
FORGE_SQL_DEFAULT_DOCKER_IMAGE="$FORGE_SQL_DOCKER_IMAGE"
FORGE_SQL_DEFAULT_DOCKER_CONTAINER="$FORGE_SQL_DOCKER_CONTAINER"
FORGE_SQL_DEFAULT_PORT="$FORGE_SQL_PORT"
FORGE_SQL_DEFAULT_DATA_BIND_PATH="$FORGE_SQL_DATA_BIND_PATH"
FORGE_SQL_DEFAULT_DATA_VOLUME_NAME="$FORGE_SQL_DATA_VOLUME_NAME"
FORGE_SQL_VERSION_REQUESTED=0
FORGE_SQL_VERSION_SPEC=""

forge_sql_known_versions() {
  cat <<'EOF'
Common SQL Server Docker versions:
  --version 2025
  --version 2022
  --version 2019
  --version 2017

You can also pass a full mssql/server tag, for example:
  --version 2019-latest
  --version 2022-CU14-ubuntu-22.04

--server is accepted as an alias of --version.

Full tag list:
  https://mcr.microsoft.com/v2/mssql/server/tags/list
EOF
}

forge_sql_resolve_image() {
  local spec="$1"

  case "$spec" in
    mcr.microsoft.com/mssql/server:*)
      printf '%s\n' "$spec"
      ;;
    *:*)
      printf '%s\n' "$spec"
      ;;
    20[0-9][0-9])
      printf 'mcr.microsoft.com/mssql/server:%s-latest\n' "$spec"
      ;;
    *)
      printf 'mcr.microsoft.com/mssql/server:%s\n' "$spec"
      ;;
  esac
}

forge_sql_image_tag() {
  local image="$1"
  printf '%s\n' "${image##*:}"
}

forge_sql_target_suffix() {
  local image="$1"
  local tag suffix

  tag="$(forge_sql_image_tag "$image")"

  case "$tag" in
    20[0-9][0-9]-latest)
      printf '%s\n' "${tag%%-*}"
      ;;
    *)
      suffix="$(printf '%s\n' "$tag" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
      [[ -n "$suffix" ]] || suffix="custom"
      printf '%s\n' "$suffix"
      ;;
  esac
}

forge_sql_host_port() {
  local suffix="$1"
  local checksum

  if [[ "$suffix" =~ ^20[0-9][0-9]$ ]]; then
    printf '%s\n' "$suffix"
    return 0
  fi

  checksum="$(printf '%s\n' "$suffix" | cksum | awk '{print $1}')"
  printf '%s\n' "$((21000 + (checksum % 1000)))"
}

forge_sql_configure_target() {
  local image="$1"
  local suffix

  FORGE_SQL_DOCKER_IMAGE="$image"
  FORGE_SQL_DOCKER_CONTAINER="$FORGE_SQL_DEFAULT_DOCKER_CONTAINER"
  FORGE_SQL_PORT="$FORGE_SQL_DEFAULT_PORT"
  FORGE_SQL_DATA_BIND_PATH="$FORGE_SQL_DEFAULT_DATA_BIND_PATH"
  FORGE_SQL_DATA_VOLUME_NAME="$FORGE_SQL_DEFAULT_DATA_VOLUME_NAME"

  if [[ "$image" == "$FORGE_SQL_DEFAULT_DOCKER_IMAGE" ]]; then
    return 0
  fi

  suffix="$(forge_sql_target_suffix "$image")"
  FORGE_SQL_DOCKER_CONTAINER="${FORGE_SQL_DEFAULT_DOCKER_CONTAINER}-${suffix}"
  if [[ -n "$FORGE_SQL_DEFAULT_DATA_BIND_PATH" ]]; then
    FORGE_SQL_DATA_BIND_PATH="${FORGE_SQL_DEFAULT_DATA_BIND_PATH}-${suffix}"
  fi
  FORGE_SQL_DATA_VOLUME_NAME="${FORGE_SQL_DEFAULT_DATA_VOLUME_NAME}-${suffix}"
  FORGE_SQL_PORT="$(forge_sql_host_port "$suffix")"
}

forge_sql_apply_version() {
  local spec="${1:-}"
  local image

  if [[ -z "$spec" ]]; then
    echo "ERROR: --version requires a version or tag." >&2
    return 1
  fi

  image="$(forge_sql_resolve_image "$spec")"
  forge_sql_configure_target "$image"
  FORGE_SQL_VERSION_REQUESTED=1
  FORGE_SQL_VERSION_SPEC="$spec"
}

forge_sql_verify_image() {
  local image="$1"

  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  if docker manifest inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: SQL Server Docker image was not found or could not be verified: $image" >&2
  echo >&2
  forge_sql_known_versions >&2
  return 1
}

forge_sql_announce_target() {
  if [[ "${FORGE_SQL_VERSION_REQUESTED:-0}" != "1" ]]; then
    return 0
  fi

  echo "SQL target: container=${FORGE_SQL_DOCKER_CONTAINER} image=${FORGE_SQL_DOCKER_IMAGE} port=${FORGE_SQL_PORT}"
}

#######################################
# Ardis migrations
#######################################
ARDIS_MIGRATIONS_PATH="$HOME/work/ardis-perform/Ardis.Migrations.Console"
ARDIS_MIGRATIONS_LIBRARY="Ardis.Migrations.Console.dll"

#######################################
# Export
#######################################
export \
  FORGE_MACHINE_NAME \
  FORGE_SCRIPT_DIR \
  FORGE_ROOT \
  FORGE_CONFIG_DIR \
  FORGE_CONFIG_LOCAL_DIR \
  FORGE_WORK_STATE_FILE \
  FORGE_SQL_LOCAL_ROOT \
  FORGE_SQL_EXTERNAL_ROOT \
  FORGE_SQL_NETWORK_ROOT \
  FORGE_SQL_LOCAL_SNAPSHOTS_PATH \
  FORGE_SQL_LOCAL_DOCKER_DATA_PATH \
  FORGE_SQL_EXTERNAL_SNAPSHOTS_PATH \
  FORGE_SQL_EXTERNAL_DOCKER_DATA_PATH \
  FORGE_SQL_NETWORK_SNAPSHOTS_PATH \
  FORGE_SQL_NETWORK_DOCKER_DATA_PATH \
  FORGE_SQL_SNAPSHOTS_PATH \
  FORGE_SQL_DATA_MOUNT_KIND \
  FORGE_SQL_DATA_BIND_PATH \
  FORGE_SQL_DOCKER_ROOT \
  FORGE_SQL_DOCKER_SNAPSHOTS_PATH \
  FORGE_SQL_DATA_VOLUME_NAME \
  FORGE_ICLOUD_ROOT \
  FORGE_ICLOUD_FORGE_DIR \
  FORGE_SECRETS_FILE \
  FORGE_SQL_DOCKER_CONTAINER \
  FORGE_SQL_USER \
  FORGE_SQL_PORT \
  FORGE_SQL_DOCKER_IMAGE \
  FORGE_SQL_DEFAULT_DOCKER_IMAGE \
  FORGE_SQL_DEFAULT_DOCKER_CONTAINER \
  FORGE_SQL_DEFAULT_PORT \
  FORGE_SQL_DEFAULT_DATA_BIND_PATH \
  FORGE_SQL_DEFAULT_DATA_VOLUME_NAME \
  FORGE_SQL_VERSION_REQUESTED \
  FORGE_SQL_VERSION_SPEC \
  FORGE_BROWSER \
  ARDIS_MIGRATIONS_PATH \
  ARDIS_MIGRATIONS_LIBRARY
