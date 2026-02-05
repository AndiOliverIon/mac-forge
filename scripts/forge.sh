#!/usr/bin/env bash
# forge.sh

#######################################
# Machine / repo
#######################################
FORGE_MACHINE_NAME="Hades"
FORGE_ROOT="$HOME/mac-forge"

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
FORGE_SECRETS_FILE="$FORGE_ICLOUD_FORGE_DIR/forge-secrets.sh"

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
  if docker_path:
    print("FORGE_SQL_DATA_BIND_PATH=" + docker_path)
  if snap_path:
    print("FORGE_SQL_SNAPSHOTS_PATH=" + snap_path)
except Exception:
  pass
PY
}

forge__apply_work_state() {
  local parsed
  parsed="$(forge__read_work_state)"
  [[ -n "${parsed//$'\n'/}" ]] || return 0
  eval "$parsed"

  # Enforce mount kind for this workflow.
  FORGE_SQL_DATA_MOUNT_KIND="bind"
}

# Apply the state immediately on source so every script gets consistent vars.
forge__apply_work_state

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
  ARDIS_MIGRATIONS_PATH \
  ARDIS_MIGRATIONS_LIBRARY
