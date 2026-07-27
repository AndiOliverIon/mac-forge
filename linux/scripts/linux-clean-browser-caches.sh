#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-browser-caches [--dry-run]

Clear Chrome per-profile disk and compiled-code caches. Profiles, credentials,
cookies, sessions, history, extensions, settings, and browser storage are kept.
EOF
}

main() {
  local root="$HOME/.cache/google-chrome"
  local uid target size total=0 status
  local targets=()

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done

  [[ -d "$root" ]] || { echo "Chrome cache directory does not exist."; exit 0; }
  [[ ! -L "$root" ]] || linux_clean_die "Refusing symlinked Chrome cache directory."
  uid="$(id -u)"

  while IFS= read -r -d '' target; do
    linux_clean_tree_is_safe "$root" "$target" "$uid" || continue
    targets+=("$target")
    size="$(linux_clean_size_kib "$target")"
    total="$((total + size))"
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type d \
    \( -name Cache -o -name 'Code Cache' \) -print0)

  echo "Chrome disk and code caches: ${#targets[@]} directories ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do
    echo "  - $target ($(linux_clean_format_gib "$(linux_clean_size_kib "$target")"))"
  done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }
  (( ${#targets[@]} > 0 )) || exit 0

  if linux_clean_process_matches '(^|/)(google-chrome|chrome)([[:space:]]|$)'; then
    echo "Chrome is running; skipping its caches."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect Chrome process state."

  for target in "${targets[@]}"; do
    linux_clean_delete_tree "$root" "$target" "$uid"
  done
  echo "Chrome deleted: ${#targets[@]}"
}

main "$@"
