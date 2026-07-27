#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-claude-cache [--dry-run]

Clear only Claude CLI's reconstructible staging cache. Credentials,
conversations, sessions, configuration, projects, MCP logs, and ~/.claude are
preserved.
EOF
}

main() {
  local root="$HOME/.cache/claude"
  local target="$root/staging"
  local uid size status

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done

  [[ -d "$root" ]] || { echo "Claude cache directory does not exist."; exit 0; }
  [[ ! -L "$root" ]] || linux_clean_die "Refusing symlinked Claude cache directory."
  uid="$(id -u)"
  if ! linux_clean_tree_is_safe "$root" "$target" "$uid"; then
    echo "Claude has no eligible staging cache."
    exit 0
  fi

  size="$(linux_clean_size_kib "$target")"
  echo "Claude staging cache: $target ($(linux_clean_format_gib "$size"))"
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }

  if linux_clean_process_matches '(^|/)(claude)([[:space:]]|$)'; then
    echo "Claude is running; skipping its staging cache."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect Claude process state."

  linux_clean_delete_tree "$root" "$target" "$uid"
  echo "Claude staging cache deleted."
}

main "$@"
