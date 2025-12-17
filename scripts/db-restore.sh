#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
else
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Helpers
#######################################
die() {
	echo "ERROR: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

load_secrets() {
	if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
		# shellcheck disable=SC1090
		source "$FORGE_SECRETS_FILE"
	fi
}

log_step() {
	echo "-> $*"
}

#######################################
# Wait for SQL Server readiness
#######################################
wait_for_sql_ready() {
	echo "Waiting for SQL Server in container '$FORGE_SQL_DOCKER_CONTAINER' to be ready..."

	local max_tries=30
	local i

	for ((i = 1; i <= max_tries; i++)); do
		if docker exec "$FORGE_SQL_DOCKER_CONTAINER" \
			/opt/mssql-tools18/bin/sqlcmd \
			-S localhost \
			-U sa \
			-P "$FORGE_SQL_SA_PASSWORD" \
			-C \
			-Q "SELECT 1" >/dev/null 2>&1; then
			echo "SQL Server is ready (attempt $i)."
			return 0
		fi

		echo "  ... not ready yet (attempt $i), retrying in 2s"
		sleep 2
	done

	die "SQL Server did not become ready after $((max_tries * 2)) seconds."
}

#######################################
# Ensure SQL container exists & is running
#######################################
ensure_sql_container() {
	require_cmd docker
	load_secrets

	: "${FORGE_SQL_DOCKER_CONTAINER:?FORGE_SQL_DOCKER_CONTAINER must be set in forge.sh}"
	: "${FORGE_DOCKER_VOLUME_ROOT:?FORGE_DOCKER_VOLUME_ROOT must be set in forge.sh}"
	: "${FORGE_SQL_DOCKER_ROOT:?FORGE_SQL_DOCKER_ROOT must be set in forge.sh}"
	: "${FORGE_SQL_DOCKER_IMAGE:?FORGE_SQL_DOCKER_IMAGE must be set in forge.sh}"
	: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set in forge-secrets.sh}"

	local name="$FORGE_SQL_DOCKER_CONTAINER"
	local image="$FORGE_SQL_DOCKER_IMAGE"
	local host_port="${FORGE_SQL_PORT:-1433}"

	# Ensure host roots exist (active root decides whether it's Acasis or local)
	mkdir -p "$FORGE_DOCKER_VOLUME_ROOT"
	mkdir -p "$FORGE_SQL_SNAPSHOTS_PATH"

	if docker ps -a --format '{{.Names}}' | grep -q "^${name}\$"; then
		log_step "Container '$name' already exists."

		if docker ps --format '{{.Names}}' | grep -q "^${name}\$"; then
			log_step "Container '$name' is already running."
		else
			log_step "Starting existing container '$name'..."
			docker start "$name" >/dev/null
		fi
	else
		log_step "Container '$name' does not exist. Creating a new SQL Server container..."
		log_step "Host volume: $FORGE_DOCKER_VOLUME_ROOT  ->  Container: $FORGE_SQL_DOCKER_ROOT"

		docker run -d \
			--name "$name" \
			-e "ACCEPT_EULA=Y" \
			-e "MSSQL_SA_PASSWORD=$FORGE_SQL_SA_PASSWORD" \
			-e "SA_PASSWORD=$FORGE_SQL_SA_PASSWORD" \
			-p "${host_port}:1433" \
			-v "$FORGE_DOCKER_VOLUME_ROOT:$FORGE_SQL_DOCKER_ROOT" \
			"$image" >/dev/null
	fi
}

#######################################
# Find .bak files (maxdepth 1)
#######################################
find_baks_in_dir() {
	local dir="$1"
	[[ -d "$dir" ]] || return 0

	find "$dir" \
		-maxdepth 1 \
		-type f \
		-iname "*.bak" \
		! -name '._*' \
		-print 2>/dev/null
}

#######################################
# Preconditions
#######################################
require_cmd docker
require_cmd fzf
load_secrets

ensure_sql_container
wait_for_sql_ready

: "${FORGE_SQL_SA_PASSWORD:?FORGE_SQL_SA_PASSWORD must be set in forge-secrets.sh}"
: "${FORGE_SQL_USER:?FORGE_SQL_USER must be set in forge.sh}"
: "${FORGE_SQL_SNAPSHOTS_PATH:?FORGE_SQL_SNAPSHOTS_PATH must be set in forge.sh}"
: "${FORGE_SQL_DOCKER_SNAPSHOTS_PATH:?FORGE_SQL_DOCKER_SNAPSHOTS_PATH must be set in forge.sh}"
: "${FORGE_SQL_ACASIS_ROOT:?FORGE_SQL_ACASIS_ROOT must be set in forge.sh}"
: "${FORGE_SQL_LOCAL_ROOT:?FORGE_SQL_LOCAL_ROOT must be set in forge.sh}"
: "${FORGE_SQL_ACASIS_IMPORT_PATH:?FORGE_SQL_ACASIS_IMPORT_PATH must be set in forge.sh}"
: "${FORGE_SQL_LOCAL_IMPORT_PATH:?FORGE_SQL_LOCAL_IMPORT_PATH must be set in forge.sh}"

# Validate snapshots mount inside container
docker exec "$FORGE_SQL_DOCKER_CONTAINER" /bin/bash -lc \
	"test -d '$FORGE_SQL_DOCKER_SNAPSHOTS_PATH' -a -w '$FORGE_SQL_DOCKER_SNAPSHOTS_PATH'" ||
	die "Snapshots path not writable in container (mount missing/misconfigured?): $FORGE_SQL_DOCKER_SNAPSHOTS_PATH"

#######################################
# Priority fallback (0-4)
#######################################
CWD="$(pwd)"
ACASIS_PRESENT="false"
if [[ -d "$FORGE_SQL_ACASIS_ROOT" ]]; then
	ACASIS_PRESENT="true"
fi

log_step "Restore search priority in effect:"
log_step "  0) current dir"
log_step "  1) if Acasis present -> snapshots"
log_step "  2) if Acasis present and no snapshots -> Acasis import"
log_step "  3) if Acasis NOT present -> local import"
log_step "  4) fail"

candidates=()
search_origin=""

# 0) current dir
mapfile -t candidates < <(find_baks_in_dir "$CWD" || true)
if ((${#candidates[@]} > 0)); then
	search_origin="current directory ($CWD)"
	log_step "Scenario 0 hit: found ${#candidates[@]} .bak file(s) in current directory."
else
	log_step "Scenario 0 miss: no .bak files in current directory ($CWD)."

	if [[ "$ACASIS_PRESENT" == "true" ]]; then
		log_step "Acasis detected at: $FORGE_SQL_ACASIS_ROOT"

		# 1) snapshots (on Acasis because active root = Acasis)
		mapfile -t candidates < <(find_baks_in_dir "$FORGE_SQL_SNAPSHOTS_PATH" || true)
		if ((${#candidates[@]} > 0)); then
			search_origin="snapshots ($FORGE_SQL_SNAPSHOTS_PATH)"
			log_step "Scenario 1 hit: found ${#candidates[@]} .bak file(s) in snapshots."
		else
			log_step "Scenario 1 miss: no .bak files in snapshots ($FORGE_SQL_SNAPSHOTS_PATH)."

			# 2) Acasis import folder
			mapfile -t candidates < <(find_baks_in_dir "$FORGE_SQL_ACASIS_IMPORT_PATH" || true)
			if ((${#candidates[@]} > 0)); then
				search_origin="Acasis import ($FORGE_SQL_ACASIS_IMPORT_PATH)"
				log_step "Scenario 2 hit: found ${#candidates[@]} .bak file(s) in Acasis import."
			else
				log_step "Scenario 2 miss: no .bak files in Acasis import ($FORGE_SQL_ACASIS_IMPORT_PATH)."
				die "No .bak files found (scenarios 0-2 exhausted with Acasis present)."
			fi
		fi
	else
		log_step "Acasis not present at: $FORGE_SQL_ACASIS_ROOT"

		# 3) local import folder
		mapfile -t candidates < <(find_baks_in_dir "$FORGE_SQL_LOCAL_IMPORT_PATH" || true)
		if ((${#candidates[@]} > 0)); then
			search_origin="local import ($FORGE_SQL_LOCAL_IMPORT_PATH)"
			log_step "Scenario 3 hit: found ${#candidates[@]} .bak file(s) in local import."
		else
			log_step "Scenario 3 miss: no .bak files in local import ($FORGE_SQL_LOCAL_IMPORT_PATH)."
			# 4) fail
			die "No .bak files found (scenarios 0-4 exhausted)."
		fi
	fi
fi

#######################################
# Select .bak via fzf
#######################################
log_step "Offering selection from: $search_origin"

selected_file="$(
	printf '%s\n' "${candidates[@]}" | fzf --prompt='Select .bak to restore > '
)" || die "No file selected."

backup_basename="$(basename "$selected_file")"

#######################################
# Derive default DB name from filename
#######################################
base="${backup_basename%.*}"  # remove extension
base="${base%%.*}"            # cut at first dot
default_db_name="${base%%_*}" # cut at first underscore
[[ -n "$default_db_name" ]] || default_db_name="$base"

echo "Selected file: $backup_basename"
echo "Default DB name: $default_db_name"

read -r -p "Database name to restore into [$default_db_name]: " db_name
db_name="${db_name:-$default_db_name}"
[[ -n "$db_name" ]] || die "Database name cannot be empty."

#######################################
# Stage into snapshots (canonical) as <db_name>.bak
#######################################
mkdir -p "$FORGE_SQL_SNAPSHOTS_PATH"
[[ -d "$FORGE_SQL_SNAPSHOTS_PATH" && -w "$FORGE_SQL_SNAPSHOTS_PATH" ]] ||
	die "Snapshots path not writable on host: $FORGE_SQL_SNAPSHOTS_PATH"

snapshot_filename="$db_name.bak"
snapshot_host_path="$FORGE_SQL_SNAPSHOTS_PATH/$snapshot_filename"
snapshot_container_path="$FORGE_SQL_DOCKER_SNAPSHOTS_PATH/$snapshot_filename"

if [[ "$selected_file" != "$snapshot_host_path" ]]; then
	log_step "Staging selected backup into snapshots (canonical storage):"
	log_step "  from: $selected_file"
	log_step "    to: $snapshot_host_path"
	cp -f "$selected_file" "$snapshot_host_path"
else
	log_step "Selected backup is already the canonical snapshot: $snapshot_host_path"
fi

# Ensure container can read the staged file
docker exec -u 0 "$FORGE_SQL_DOCKER_CONTAINER" /bin/bash -lc "
	chown mssql:mssql '$snapshot_container_path' 2>/dev/null || true
	chmod 660 '$snapshot_container_path' 2>/dev/null || true
"

[[ -f "$snapshot_host_path" ]] || die "Snapshot not found on host after staging: $snapshot_host_path"

#######################################
# Restore (WITH MOVE auto-generated from FILELISTONLY)
#######################################
log_step "Inspecting backup file list to generate WITH MOVE..."

SQL_DATA_DIR="/var/opt/mssql/data"

filelist_csv="$(
	docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
		/opt/mssql-tools18/bin/sqlcmd \
		-S localhost \
		-U "$FORGE_SQL_USER" \
		-P "$FORGE_SQL_SA_PASSWORD" \
		-C \
		-W -h -1 -s '|' <<SQL_EOF
SET NOCOUNT ON;
RESTORE FILELISTONLY
FROM DISK = N'$snapshot_container_path';
SQL_EOF
)" || die "Failed to read FILELISTONLY from backup."

move_clauses="$(
	echo "$filelist_csv" | awk -F'|' -v db="$db_name" -v dir="$SQL_DATA_DIR" '
		BEGIN { d=0; l=0; }
		{
			logical=$1;
			type=$3;

			# Trim whitespace
			gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", logical);
			gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", type);

			if (type == "D") {
				d++;
				suffix = (d == 1 ? "" : "_" d);
				target = dir "/" db suffix ".mdf";
				printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target);
			}
			else if (type == "L") {
				l++;
				suffix = (l == 1 ? "" : "_" l);
				target = dir "/" db "_log" suffix ".ldf";
				printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target);
			}
		}
	' | sed '$ s/,$//'
)"

[[ -n "$move_clauses" ]] || die "Could not generate MOVE clauses (FILELISTONLY output empty?)."

log_step "Restoring database [$db_name] from snapshot: $snapshot_container_path"
log_step "MOVE mapping:"
echo "$move_clauses" | sed 's/^/  /'

docker exec -i "$FORGE_SQL_DOCKER_CONTAINER" \
	/opt/mssql-tools18/bin/sqlcmd \
	-S localhost \
	-U "$FORGE_SQL_USER" \
	-P "$FORGE_SQL_SA_PASSWORD" \
	-C \
	-b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
	BEGIN
		PRINT 'Database $db_name exists -> setting SINGLE_USER...';
		ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	END;

	PRINT 'Restoring database $db_name from $snapshot_container_path...';

	RESTORE DATABASE [$db_name]
	FROM DISK = N'$snapshot_container_path'
	WITH
		REPLACE,
		RECOVERY,
		$move_clauses;

	ALTER DATABASE [$db_name] SET MULTI_USER;
	PRINT 'Restore completed successfully.';
END TRY
BEGIN CATCH
	DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
	PRINT 'RESTORE FAILED: ' + @msg;
	RAISERROR(@msg, 16, 1);
END CATCH
SQL_EOF

echo "OK: Database [$db_name] restored successfully."
echo "Snapshot used from:"
echo "  $snapshot_host_path"
