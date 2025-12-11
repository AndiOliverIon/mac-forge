#!/usr/bin/env bash
# forge.sh
# Central config file for mac-forge scripts.
# Other scripts must `source` this file.

#######################################
# General
#######################################
FORGE_MACHINE_NAME="Hades"
FORGE_ROOT="$HOME/mac-forge"

#######################################
# Paths
#######################################
# Detect SQL root dynamically
if [[ -d "/Volumes/shared/sql" ]]; then
	# Acasis connected
	FORGE_SQL_PATH="/Volumes/shared/sql"
else
	# Fallback to local SQL folder
	FORGE_SQL_PATH="$HOME/sql"
fi

# iCloud forge folder (for private configs)
FORGE_ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
FORGE_ICLOUD_FORGE_DIR="$FORGE_ICLOUD_ROOT/forge"
FORGE_SECRETS_FILE="$FORGE_ICLOUD_FORGE_DIR/forge-secrets.sh"

# Host side: everything Docker-related lives under sql/docker on Acasis
FORGE_DOCKER_VOLUME_ROOT="$FORGE_SQL_PATH/docker"

# Host folders on Acasis
FORGE_SQL_BACKUP_HOST_PATH="$FORGE_DOCKER_VOLUME_ROOT/backups"
FORGE_SQL_SNAPSHOTS_PATH="$FORGE_DOCKER_VOLUME_ROOT/snapshots"

# Container side root
FORGE_SQL_DOCKER_ROOT="/var/opt/mssql"
FORGE_SQL_DOCKER_BACKUP_PATH="$FORGE_SQL_DOCKER_ROOT/backups"

# Paths inside the container
FORGE_SQL_DOCKER_ROOT="/var/opt/mssql"

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
# Perform
#######################################
PERFORM_ROOT="${PERFORM_ROOT:-$HOME/work/ardis-perform}"
PERFORM_WEB_PROJECT="${PERFORM_WEB_PROJECT:-Asms2.Web}"

#######################################
# System paths
#######################################
# Path to libgdiplus from Homebrew (tweak if your brew path changes)
LIBGDIPLUS_PATH="${LIBGDIPLUS_PATH:-/opt/homebrew/opt/mono-libgdiplus/lib/libgdiplus.dylib}"

#######################################
# Export
#######################################
export \
	FORGE_MACHINE_NAME \
	FORGE_ROOT \
	FORGE_SQL_PATH \
	FORGE_DOCKER_VOLUME_ROOT \
	FORGE_ICLOUD_ROOT \
	FORGE_ICLOUD_FORGE_DIR \
	FORGE_SECRETS_FILE \
	FORGE_SQL_DOCKER_CONTAINER \
	FORGE_SQL_PORT \
	FORGE_SQL_DOCKER_ROOT \
	FORGE_SQL_DOCKER_BACKUP_PATH \
	FORGE_SQL_DOCKER_IMAGE \
	ARDIS_MIGRATIONS_PATH \
	ARDIS_MIGRATIONS_LIBRARY \
	PERFORM_ROOT \
	PERFORM_WEB_PROJECT \
	LIBGDIPLUS_PATH
