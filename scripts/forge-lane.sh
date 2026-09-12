#!/usr/bin/env bash
# forge-lane.sh — agent-universe (Raynor/Zeratul) project discovery for Bash
# tooling. Mirrors linux/aliases.zsh's __forge_lane_root/__forge_project_cd
# logic so non-interactive scripts (e.g. vps1-db-migrate.sh, ardis-migrate.sh)
# find a project's in-universe clone instead of always using the shared
# "work" lane, when run inside a Raynor or Zeratul agent session.
#
# Sourced by scripts that need lane-aware path resolution; does not run
# standalone.

#######################################
# forge_lane_root
# Prints the active agent-universe root when the current shell is physically
# inside it (matches PWD first, same as the zsh alias), or when
# FORGE_UNIVERSE_ROOT names one. Prints nothing outside a known universe.
#######################################
forge_lane_root() {
  case "$PWD" in
    /home/oliver/raynor | /home/oliver/raynor/*)
      printf '%s\n' /home/oliver/raynor
      return 0
      ;;
    /home/oliver/zeratul | /home/oliver/zeratul/*)
      printf '%s\n' /home/oliver/zeratul
      return 0
      ;;
  esac

  case "${FORGE_UNIVERSE_ROOT:-}" in
    /home/oliver/raynor | /home/oliver/zeratul)
      printf '%s\n' "$FORGE_UNIVERSE_ROOT"
      return 0
      ;;
  esac

  return 0
}

#######################################
# forge_resolve_lane_path <default_path> <work_root>
# Rewrites <default_path> (rooted at <work_root>, e.g. "$HOME/work") onto the
# active agent-universe root when one is active and the same relative project
# exists there. Falls back to <default_path> unchanged when there is no
# active lane or no matching clone in it.
#######################################
forge_resolve_lane_path() {
  local default_path="$1" work_root="$2" lane_root relative candidate

  lane_root="$(forge_lane_root)"
  if [[ -z "$lane_root" || -z "$work_root" ]]; then
    printf '%s\n' "$default_path"
    return 0
  fi

  case "$default_path" in
    "$work_root"/*)
      relative="${default_path#"$work_root"/}"
      candidate="$lane_root/$relative"
      if [[ -e "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$default_path"
}
