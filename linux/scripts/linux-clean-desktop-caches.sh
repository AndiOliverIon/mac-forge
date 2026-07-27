#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=linux-clean-common.sh
source "$SCRIPT_DIR/linux-clean-common.sh"

usage() {
  cat <<'EOF'
Usage: linux-clean-desktop-caches [--dry-run]

Clear only reconstructible thumbnail and GPU shader caches. Desktop settings,
sessions, application data, and credentials are preserved. This cleaner is
full-only and skips while related desktop applications are running.
EOF
}

main() {
  local root="$HOME/.cache" uid target total=0 status
  local targets=()

  linux_clean_parse_dry_run "$@" || { usage; exit 0; }
  linux_clean_require_linux
  for command in awk du find grep id pgrep rm stat; do
    linux_clean_require_cmd "$command"
  done
  [[ -d "$root" && ! -L "$root" ]] || linux_clean_die "Unsafe user cache root."
  uid="$(id -u)"

  for target in "$root/thumbnails" "$root/mesa_shader_cache" \
    "$root/qtshadercache-x86_64-little_endian-lp64"; do
    linux_clean_tree_is_safe "$root" "$target" "$uid" || continue
    targets+=("$target")
    total="$((total + $(linux_clean_size_kib "$target")))"
  done

  echo "Desktop thumbnail and shader caches: ${#targets[@]} ($(linux_clean_format_gib "$total"))"
  for target in "${targets[@]}"; do echo "  - $target"; done
  (( LINUX_CLEAN_DRY_RUN )) && { echo "Dry run: nothing was deleted."; exit 0; }

  if linux_clean_process_matches '(^|/)(plasmashell|kwin_wayland|google-chrome|rider)([[:space:]]|$)'; then
    echo "The desktop or a GPU-using application is running; skipping desktop caches."
    exit 0
  else
    status=$?
  fi
  (( status == 1 )) || linux_clean_die "Could not inspect desktop process state."

  for target in "${targets[@]}"; do
    linux_clean_delete_tree "$root" "$target" "$uid"
  done
  echo "Desktop caches deleted: ${#targets[@]}"
}

main "$@"
