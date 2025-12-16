#!/usr/bin/env bash
# forge.sh

#######################################
# Machine / repo
#######################################
FORGE_MACHINE_NAME="Hades"
FORGE_ROOT="$HOME/mac-forge"

#######################################
# Storage roots (EDIT THESE ON DEMAND)
#######################################
# Acasis root (external)
FORGE_SQL_ACASIS_ROOT="/Volumes/shared/sql"

# Local root (internal storage)
FORGE_SQL_LOCAL_ROOT="$HOME/sql" # (on your machine: /Users/oliver/sql)

#######################################
# Active root selection (Acasis if present, else local)
#######################################
if [[ -d "$FORGE_SQL_ACASIS_ROOT" ]]; then
	FORGE_SQL_PATH="$FORGE_SQL_ACASIS_ROOT"
else
	FORGE_SQL_PATH="$FORGE_SQL_LOCAL_ROOT"
fi

#######################################
# iCloud forge folder (for private configs)
#######################################
FORGE_ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
FORGE_ICLOUD_FORGE_DIR="$FORGE_ICLOUD_ROOT/forge"
FORGE_SECRETS_FILE="$FORGE_ICLOUD_FORGE_DIR/forge-secrets.sh"

#######################################
# Docker volume root (under the ACTIVE root)
#######################################
FORGE_DOCKER_VOLUME_ROOT="$FORGE_SQL_PATH/docker"

#######################################
# Snapshots (ONLY canonical storage for restore/snapshot)
#######################################
FORGE_SQL_SNAPSHOTS_PATH="$FORGE_DOCKER_VOLUME_ROOT/snapshots"

# Container side root (mounted)
FORGE_SQL_DOCKER_ROOT="/var/opt/mssql"
FORGE_SQL_DOCKER_SNAPSHOTS_PATH="$FORGE_SQL_DOCKER_ROOT/snapshots"

#######################################
# Restore import locations (EDIT THESE ON DEMAND)
#######################################
# If Acasis is present and snapshots folder has no .bak, look here next:
FORGE_SQL_ACASIS_IMPORT_PATH="$FORGE_SQL_ACASIS_ROOT"

# If Acasis is NOT present, look here:
FORGE_SQL_LOCAL_IMPORT_PATH="$FORGE_SQL_LOCAL_ROOT"

#######################################
# Docker / SQL Server
#######################################
FORGE_SQL_DOCKER_CONTAINER="forge-sql"
FORGE_SQL_USER="sa"
FORGE_SQL_PORT="${FORGE_SQL_PORT:-2022}"
FORGE_SQL_DOCKER_IMAGE="${FORGE_SQL_DOCKER_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"

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
	FORGE_SQL_ACASIS_ROOT \
	FORGE_SQL_LOCAL_ROOT \
	FORGE_SQL_PATH \
	FORGE_DOCKER_VOLUME_ROOT \
	FORGE_SQL_SNAPSHOTS_PATH \
	FORGE_SQL_DOCKER_ROOT \
	FORGE_SQL_DOCKER_SNAPSHOTS_PATH \
	FORGE_SQL_ACASIS_IMPORT_PATH \
	FORGE_SQL_LOCAL_IMPORT_PATH \
	FORGE_ICLOUD_ROOT \
	FORGE_ICLOUD_FORGE_DIR \
	FORGE_SECRETS_FILE \
	FORGE_SQL_DOCKER_CONTAINER \
	FORGE_SQL_USER \
	FORGE_SQL_PORT \
	FORGE_SQL_DOCKER_IMAGE \
	ARDIS_MIGRATIONS_PATH \
	ARDIS_MIGRATIONS_LIBRARY
