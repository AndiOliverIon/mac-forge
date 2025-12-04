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
# Network SQL share from Thanatos
FORGE_SQL_PATH="/Volumes/shared/sql"

# iCloud forge folder (for private configs)
FORGE_ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
FORGE_ICLOUD_FORGE_DIR="$FORGE_ICLOUD_ROOT/forge"
FORGE_SECRETS_FILE="$FORGE_ICLOUD_FORGE_DIR/forge-secrets.sh"

#######################################
# Docker / SQL Server
#######################################
FORGE_SQL_DOCKER_CONTAINER="forge-sql"
FORGE_SQL_DOCKER_BACKUP_PATH="/var/opt/mssql/backups"

#######################################
# Export
#######################################
export \
  FORGE_MACHINE_NAME \
  FORGE_ROOT \
  FORGE_SQL_PATH \
  FORGE_ICLOUD_ROOT \
  FORGE_ICLOUD_FORGE_DIR \
  FORGE_SECRETS_FILE \
  FORGE_SQL_DOCKER_CONTAINER \
  FORGE_SQL_DOCKER_BACKUP_PATH
