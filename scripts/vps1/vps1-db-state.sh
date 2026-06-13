#!/opt/homebrew/bin/bash
# vps1-db-state.sh — bring vps1 user databases ONLINE or OFFLINE.
#
# Usage:
#   vps1-db-state.sh online    # pick from OFFLINE databases, bring them ONLINE
#   vps1-db-state.sh offline   # pick from ONLINE databases, take them OFFLINE
#
# Aliases: v1-sql-up (= online), v1-sql-down (= offline).
#
# The picker is an interactive fzf loop: mark one or more databases (Enter
# toggles), pick "[ DONE ]" to apply. The list always shows what you have
# chosen (✔) next to what remains available. Once DONE is selected, each chosen
# database is switched to the requested state with its own ALTER DATABASE call.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Parse mode
#######################################
MODE="${1:-}"
case "$MODE" in
  online)
    TARGET_STATE="ONLINE"
    WANT_STATE="OFFLINE"        # only offline databases can be brought online
    ALTER_SUFFIX=""             # ALTER DATABASE [x] SET ONLINE;
    ACTION_LABEL="bring ONLINE"
    ;;
  offline)
    TARGET_STATE="OFFLINE"
    WANT_STATE="ONLINE"         # only online databases can be taken offline
    ALTER_SUFFIX=" WITH ROLLBACK IMMEDIATE"
    ACTION_LABEL="take OFFLINE"
    ;;
  *)
    vps1_die "Usage: $(basename "$0") {online|offline}"
    ;;
esac

#######################################
# Preconditions
#######################################
vps1_require_cmd sqlcmd
vps1_require_cmd fzf
vps1_load_connection
vps1_wait_for_sql_ready

#######################################
# Candidate databases (matching the source state)
#######################################
vps1_log_step "Retrieving $WANT_STATE databases on vps1..."
mapfile -t CANDIDATES < <(
  vps1_sqlcmd -h -1 -W -Q \
    "SET NOCOUNT ON; SELECT name FROM sys.databases
       WHERE name NOT IN ('master','tempdb','model','msdb')
         AND state_desc = '$WANT_STATE'
       ORDER BY name;" \
    | tr -d '\r' | sed '/^$/d'
)
((${#CANDIDATES[@]} > 0)) || vps1_die "No $WANT_STATE user databases found on vps1 (nothing to $ACTION_LABEL)."

#######################################
# Interactive multi-select picker
#   - remaining[]  : not yet chosen
#   - chosen[]     : marked for the action
#######################################
DONE_LABEL="[ DONE ]"
declare -a remaining=("${CANDIDATES[@]}")
declare -a chosen=()

array_contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

while true; do
  menu=()
  menu+=("$DONE_LABEL")
  for db in "${chosen[@]}"; do menu+=("✔  $db"); done
  for db in "${remaining[@]}"; do menu+=("   $db"); done

  header="Action: $ACTION_LABEL  |  chosen: ${#chosen[@]}  remaining: ${#remaining[@]}"
  sel="$(
    printf '%s\n' "${menu[@]}" \
      | fzf --prompt="$ACTION_LABEL > " \
            --header="$header"$'\n'"Enter toggles a database · pick [ DONE ] to apply"
  )" || vps1_die "Cancelled (no changes made)."

  [[ "$sel" == "$DONE_LABEL" ]] && break

  # Strip the marker prefix (✔/spaces) to recover the bare database name.
  name="${sel#✔}"
  name="${name#"${name%%[![:space:]]*}"}"

  if array_contains "$name" "${chosen[@]:+${chosen[@]}}"; then
    # Toggle off: chosen -> remaining
    new_chosen=()
    for db in "${chosen[@]}"; do [[ "$db" == "$name" ]] || new_chosen+=("$db"); done
    chosen=("${new_chosen[@]:+${new_chosen[@]}}")
    remaining+=("$name")
    IFS=$'\n' remaining=($(sort <<< "${remaining[*]}")); unset IFS
  else
    # Toggle on: remaining -> chosen
    new_remaining=()
    for db in "${remaining[@]}"; do [[ "$db" == "$name" ]] || new_remaining+=("$db"); done
    remaining=("${new_remaining[@]:+${new_remaining[@]}}")
    chosen+=("$name")
  fi
done

((${#chosen[@]} > 0)) || vps1_die "No databases selected (nothing to $ACTION_LABEL)."

#######################################
# Apply: one ALTER DATABASE per chosen database
#######################################
echo
echo "About to $ACTION_LABEL ${#chosen[@]} database(s) on vps1 ($VPS1_SQL_SERVER):"
for db in "${chosen[@]}"; do echo "    • $db"; done
echo
read -r -p "Proceed? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || vps1_die "Aborted (no changes made)."

failed=0
for db in "${chosen[@]}"; do
  vps1_log_step "Setting [$db] $TARGET_STATE..."
  if vps1_sqlcmd -b -Q "ALTER DATABASE [$db] SET $TARGET_STATE$ALTER_SUFFIX;" 2>/dev/null; then
    echo "✔ [$db] is now $TARGET_STATE."
  else
    echo "✖ Failed to set [$db] $TARGET_STATE." >&2
    failed=$((failed + 1))
  fi
done

((failed == 0)) || vps1_die "$failed database(s) failed to switch to $TARGET_STATE."
echo "✔ Done — ${#chosen[@]} database(s) set $TARGET_STATE on vps1."
