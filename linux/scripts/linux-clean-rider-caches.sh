#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-rider-caches [--dry-run]

Clear Rider indexes, IDE caches, local ReSharper caches, and temporary files.
Local History, file history, settings, projects, VCS state, plugins, credentials,
models, and JCEF application data are kept.
EOF
}

main() {
  local root="$HOME/.cache/JetBrains"
  local uid version relative target total=0 status
  local targets=()
  local allowed=(caches index resharper-host/local resharper-host/temp tmp)

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done

  [[ -d "$root" ]] || { echo "JetBrains cache directory does not exist."; exit 0; }
  [[ ! -L "$root" ]] || linux_clean_die "Refusing symlinked JetBrains cache directory."
  uid="$(id -u)"

  while IFS= read -r -d '' version; do
    for relative in "${allowed[@]}"; do
      target="$version/$relative"
      linux_clean_tree_is_safe "$root" "$target" "$uid" || continue
      targets+=("$target")
      total="$((total + $(linux_clean_size_kib "$target")))"
    done
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -name 'Rider20*' -print0)

  echo "Rider reconstructible caches: ${#targets[@]} directories ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do
    echo "  - $target ($(linux_clean_format_gib "$(linux_clean_size_kib "$target")"))"
  done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }
  (( ${#targets[@]} > 0 )) || exit 0

  if linux_clean_process_matches '(^|/)(rider|jetbrains_client|ReSharperHost)([[:space:]]|$)'; then
    echo "Rider or one of its helpers is running; skipping Rider caches."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect Rider process state."

  for target in "${targets[@]}"; do
    linux_clean_delete_tree "$root" "$target" "$uid"
  done
  echo "Rider deleted: ${#targets[@]}"
}

main "$@"
