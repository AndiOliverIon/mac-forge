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
# Work state (derived)
#
# These are set based on configs/work-state.json:
#   FORGE_WORK_STORAGE: external | network | offline
#   FORGE_WORK_CONTAINER: external | internal
#
# And then effective paths:
#   FORGE_SQL_SNAPSHOTS_PATH
#   FORGE_SQL_DATA_MOUNT_KIND: bind | named
#   FORGE_SQL_DATA_BIND_PATH (when bind)
#######################################
FORGE_WORK_STORAGE="${FORGE_WORK_STORAGE:-offline}"
FORGE_WORK_CONTAINER="${FORGE_WORK_CONTAINER:-internal}"

# Defaults (offline + internal container)
FORGE_SQL_SNAPSHOTS_PATH="${FORGE_SQL_LOCAL_SNAPSHOTS_PATH}"
FORGE_SQL_DATA_MOUNT_KIND="named"
FORGE_SQL_DATA_BIND_PATH=""

#######################################
# Helpers (used by scripts that source forge.sh)
#######################################
forge__detect_acasis_sql_root() {
  # Try to find ".../acasis" under /Volumes and return ".../acasis/sql" if present.
  # This is intentionally conservative (fast, shallow).
  local candidate=""
  for d in /Volumes/*; do
    [[ -d "$d" ]] || continue
    if [[ -d "$d/acasis" ]]; then
      candidate="$d/acasis/sql"
      break
    fi
    # also handle when the volume itself is named "acasis"
    if [[ "$(basename "$d")" == "acasis" ]]; then
      candidate="$d/sql"
      break
    fi
  done

  if [[ -n "$candidate" && -d "$candidate" ]]; then
    echo "$candidate"
  fi
}

forge__read_work_state() {
  local f="$FORGE_WORK_STATE_FILE"
  [[ -f "$f" ]] || return 0

  # Use python3 to read JSON (avoid jq dependency).
  local parsed
  parsed="$(python3 - <<'PY' "$f" 2>/dev/null || true
import json, sys
p = sys.argv[1]
try:
  with open(p, "r", encoding="utf-8") as fp:
    j = json.load(fp)
  storage = (j.get("storage") or "").strip()
  container = (j.get("container") or "").strip()
  print(storage + "\n" + container)
except Exception:
  pass
PY
)"
  [[ -n "${parsed//$'\n'/}" ]] || return 0

  local storage container
  storage="$(printf '%s' "$parsed" | sed -n '1p')"
  container="$(printf '%s' "$parsed" | sed -n '2p')"

  [[ -n "$storage" ]] && FORGE_WORK_STORAGE="$storage"
  [[ -n "$container" ]] && FORGE_WORK_CONTAINER="$container"
}

forge__apply_work_state() {
  # 1) Load last saved state (if present)
  forge__read_work_state

  # 2) Resolve storage -> effective snapshots + external docker-data roots
  case "$FORGE_WORK_STORAGE" in
    external)
      # auto-detect if your default isn't mounted
      if [[ ! -d "$FORGE_SQL_EXTERNAL_ROOT" ]]; then
        local detected
        detected="$(forge__detect_acasis_sql_root || true)"
        if [[ -n "$detected" ]]; then
          FORGE_SQL_EXTERNAL_ROOT="$detected"
          FORGE_SQL_EXTERNAL_SNAPSHOTS_PATH="${FORGE_SQL_EXTERNAL_ROOT}/snapshots"
          FORGE_SQL_EXTERNAL_DOCKER_DATA_PATH="${FORGE_SQL_EXTERNAL_ROOT}/docker-mssql"
        fi
      fi
      FORGE_SQL_SNAPSHOTS_PATH="$FORGE_SQL_EXTERNAL_SNAPSHOTS_PATH"
      FORGE_SQL_DATA_BIND_PATH="$FORGE_SQL_EXTERNAL_DOCKER_DATA_PATH"
      ;;
    network)
      FORGE_SQL_SNAPSHOTS_PATH="$FORGE_SQL_NETWORK_SNAPSHOTS_PATH"
      FORGE_SQL_DATA_BIND_PATH="$FORGE_SQL_NETWORK_DOCKER_DATA_PATH"
      ;;
    offline|*)
      FORGE_WORK_STORAGE="offline"
      FORGE_SQL_SNAPSHOTS_PATH="$FORGE_SQL_LOCAL_SNAPSHOTS_PATH"
      FORGE_SQL_DATA_BIND_PATH="$FORGE_SQL_LOCAL_DOCKER_DATA_PATH"
      ;;
  esac

  # 3) Resolve container mode -> mount kind
  case "$FORGE_WORK_CONTAINER" in
    external)
      FORGE_SQL_DATA_MOUNT_KIND="bind"
      ;;
    internal|*)
      FORGE_WORK_CONTAINER="internal"
      FORGE_SQL_DATA_MOUNT_KIND="named"
      ;;
  esac
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
  FORGE_WORK_STATE_FILE \
  FORGE_WORK_STORAGE \
  FORGE_WORK_CONTAINER \
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