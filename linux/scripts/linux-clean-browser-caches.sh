#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-browser-caches [--dry-run]

Clear Chrome and Brave per-profile disk and compiled-code caches. Profiles,
credentials, cookies, sessions, history, extensions, settings, and browser
storage are kept.
EOF
}

clean_browser() {
  local name="$1"
  local root="$2"
  local process_pattern="$3"
  local uid target size total=0 status
  local targets=()

  [[ -d "$root" ]] || { echo "$name cache directory does not exist."; return 0; }
  [[ ! -L "$root" ]] || linux_clean_die "Refusing symlinked $name cache directory."
  uid="$(id -u)"

  while IFS= read -r -d '' target; do
    linux_clean_tree_is_safe "$root" "$target" "$uid" || continue
    targets+=("$target")
    size="$(linux_clean_size_kib "$target")"
    total="$((total + size))"
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type d \
    \( -name Cache -o -name 'Code Cache' \) -print0)

  echo "$name disk and code caches: ${#targets[@]} directories ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do
    echo "  - $target ($(linux_clean_format_gib "$(linux_clean_size_kib "$target")"))"
  done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; return 0; }
  (( ${#targets[@]} > 0 )) || return 0

  if linux_clean_process_matches "$process_pattern"; then
    echo "$name is running; skipping its caches."
    return 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect $name process state."

  for target in "${targets[@]}"; do
    linux_clean_delete_tree "$root" "$target" "$uid"
  done
  echo "$name deleted: ${#targets[@]}"
}

main() {
  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done

  clean_browser \
    "Chrome" \
    "$HOME/.cache/google-chrome" \
    '(^|/)(google-chrome|chrome)([[:space:]]|$)'
  clean_browser \
    "Brave" \
    "$HOME/.cache/BraveSoftware/Brave-Browser" \
    '(^|/)(brave-browser|brave)([[:space:]]|$)'
}

main "$@"
