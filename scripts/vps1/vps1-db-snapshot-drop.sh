#!/opt/homebrew/bin/bash
# vps1-db-snapshot-drop.sh — delete .bak snapshot files from the dedicated vps1
# snapshots folder (the stored backups, NOT the live databases).
#
# Safety: multi-select the snapshots to remove, then type 'delete' to confirm.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

#######################################
# Preconditions
#######################################
vps1_require_cmd fzf
vps1_require_cmd ssh

#######################################
# Pick .bak snapshots to delete
#######################################
mapfile -t BAKS < <(vps1_list_snapshots)
((${#BAKS[@]} > 0)) || vps1_die "No .bak files in vps1 snapshots dir: $VPS1_SNAPSHOTS_HOST_DIR"

mapfile -t SELECTED < <(
  printf '%s\n' "${BAKS[@]}" \
    | fzf --multi --prompt='Select vps1 .bak snapshot(s) to DELETE > ' \
          --header='TAB to mark multiple, ENTER to confirm selection' \
          --height=60% --reverse
)
((${#SELECTED[@]} > 0)) || vps1_die "No snapshot selected."

#######################################
# Strict confirmation
#######################################
echo
echo "⚠ You are about to PERMANENTLY DELETE these snapshot file(s) on vps1:"
for name in "${SELECTED[@]}"; do
  echo "    $VPS1_SNAPSHOTS_HOST_DIR/$name"
done
echo "  Host: $VPS1_SSH_HOST"
echo
echo "Type 'delete' to confirm."
read -r -p "> " answer
[[ "$answer" == "delete" ]] || vps1_die "Confirmation mismatch. Aborted (nothing was deleted)."

#######################################
# Delete
#######################################
for name in "${SELECTED[@]}"; do
  vps1_log_step "Deleting snapshot [$name] on vps1..."
  vps1_ssh "docker exec -u 0 '$VPS1_SQL_CONTAINER' rm -f -- '$VPS1_SNAPSHOTS_CONTAINER_DIR/$name'"
done

echo "✔ Deleted ${#SELECTED[@]} snapshot(s) on vps1."
