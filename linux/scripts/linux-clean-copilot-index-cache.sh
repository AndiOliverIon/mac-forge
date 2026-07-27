#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-copilot-index-cache [--dry-run]

Clear only reconstructible GitHub Copilot project-context and project-index
caches. Authentication, sessions, configuration, plugins, and runtime packages
are kept.
EOF
}

main() {
  local root="$HOME/.cache/github-copilot"
  local uid target total=0 status
  local targets=()

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done

  [[ -d "$root" ]] || { echo "GitHub Copilot cache directory does not exist."; exit 0; }
  [[ ! -L "$root" ]] || linux_clean_die "Refusing symlinked GitHub Copilot cache directory."
  uid="$(id -u)"
  for target in "$root/project-context" "$root/project-index"; do
    linux_clean_tree_is_safe "$root" "$target" "$uid" || continue
    targets+=("$target")
    total="$((total + $(linux_clean_size_kib "$target")))"
  done

  echo "Copilot project caches: ${#targets[@]} directories ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do echo "  - $target"; done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }
  (( ${#targets[@]} > 0 )) || exit 0

  if linux_clean_process_matches '(^|/)(code|rider|copilot|copilot-language-server)([[:space:]]|$)'; then
    echo "Copilot, VS Code, or Rider is running; skipping Copilot project caches."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect Copilot process state."

  for target in "${targets[@]}"; do
    linux_clean_delete_tree "$root" "$target" "$uid"
  done
  echo "Copilot deleted: ${#targets[@]}"
}

main "$@"
