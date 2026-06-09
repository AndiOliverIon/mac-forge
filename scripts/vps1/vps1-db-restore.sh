#!/opt/homebrew/bin/bash
# vps1-db-restore.sh — restore a .bak from the dedicated vps1 snapshots folder
# into the vps1 SQL Server, proposing a database name from the file name.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd sqlcmd
vps1_require_cmd fzf
vps1_require_cmd ssh
vps1_load_connection
vps1_wait_for_sql_ready

#######################################
# Pick a .bak from the vps1 snapshots folder
#######################################
mapfile -t BAKS < <(vps1_list_snapshots)
((${#BAKS[@]} > 0)) || vps1_die "No .bak files in vps1 snapshots dir: $VPS1_SNAPSHOTS_HOST_DIR"

selected="$(printf '%s\n' "${BAKS[@]}" | fzf --prompt='Select vps1 .bak to restore > ')" \
  || vps1_die "No file selected."

#######################################
# Derive default DB name from filename
#######################################
base="${selected%.*}"   # remove extension
base="${base%%.*}"      # cut at first dot
default_db_name="${base%%_*}"  # cut at first underscore
[[ -n "$default_db_name" ]] || default_db_name="$base"

echo "Selected: $selected"
read -r -p "Database name to restore into [$default_db_name]: " db_name
db_name="${db_name:-$default_db_name}"
[[ -n "$db_name" ]] || vps1_die "Database name cannot be empty."

container_path="${VPS1_SNAPSHOTS_CONTAINER_DIR}/${selected}"

#######################################
# Generate WITH MOVE from FILELISTONLY
#######################################
filelist_csv="$(
  vps1_sqlcmd -r 1 -W -h -1 -s '|' -w 65535 -Q \
    "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$container_path';"
)" || vps1_die "Failed to read FILELISTONLY from backup."

[[ -n "${filelist_csv//$'\n'/}" ]] || vps1_die "FILELISTONLY returned no output for: $container_path"

move_clauses="$(
  echo "$filelist_csv" | awk -F'|' -v db="$db_name" -v dir="$VPS1_SQL_DATA_DIR" '
    function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
    BEGIN { d=0; l=0; }
    {
      if (NF < 2) next
      logical = trim($1)

      type = ""
      for (i=1; i<=NF; i++) {
        f = trim($i)
        if (f == "D" || f == "L") { type = f; break }
      }

      if (logical == "" || type == "") next

      if (type == "D") {
        d++
        suffix = (d == 1 ? "" : "_" d)
        target = dir "/" db suffix ".mdf"
        printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target)
      } else if (type == "L") {
        l++
        suffix = (l == 1 ? "" : "_" l)
        target = dir "/" db "_log" suffix ".ldf"
        printf("MOVE N'\''%s'\'' TO N'\''%s'\'',\n", logical, target)
      }
    }
  ' | sed '$ s/,$//'
)"

[[ -n "$move_clauses" ]] || vps1_die "Could not generate MOVE clauses."

#######################################
# Restore
#######################################
vps1_log_step "Restoring [$db_name] on vps1 from: $container_path"

vps1_sqlcmd -b <<SQL_EOF
SET NOCOUNT ON;

BEGIN TRY
  IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$db_name')
  BEGIN
    DECLARE @state nvarchar(60) = (SELECT state_desc FROM sys.databases WHERE name = N'$db_name');

    IF @state = N'RESTORING'
    BEGIN
      BEGIN TRY
        RESTORE DATABASE [$db_name] WITH RECOVERY;
      END TRY
      BEGIN CATCH
        DROP DATABASE [$db_name];
      END CATCH
    END;

    ALTER DATABASE [$db_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  END;

  RESTORE DATABASE [$db_name]
  FROM DISK = N'$container_path'
  WITH
    REPLACE,
    RECOVERY,
    $move_clauses;

  ALTER DATABASE [$db_name] SET MULTI_USER;
END TRY
BEGIN CATCH
  DECLARE
    @num int = ERROR_NUMBER(),
    @sev int = ERROR_SEVERITY(),
    @st  int = ERROR_STATE(),
    @ln  int = ERROR_LINE(),
    @msg nvarchar(4000) = ERROR_MESSAGE();

  PRINT CONCAT('RESTORE FAILED (', @num, ', sev ', @sev, ', state ', @st, ', line ', @ln, '): ', @msg);
  THROW;
END CATCH
SQL_EOF

echo "✔ Database [$db_name] restored on vps1."
echo "  Source snapshot: $VPS1_SNAPSHOTS_HOST_DIR/$selected"
