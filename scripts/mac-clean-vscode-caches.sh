#!/usr/bin/env bash
set -euo pipefail

CODE_ROOT="$HOME/Library/Application Support/Code"

CACHE_SUBDIRS=(
  "Cache"
  "CachedData"
  "Code Cache"
  "GPUCache"
)

TARGETS=()
TARGET_SIZES_KIB=()

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-vscode-caches [--dry-run]

Delete Visual Studio Code's reconstructable caches (Cache, CachedData,
Code Cache, GPUCache). Settings, keybindings, extensions, and workspace state
are preserved; VS Code rebuilds these caches on the next launch.

Options:
  -n, --dry-run Show the targeted cache directories and their size only.
  -h, --help    Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not available."
}

candidate_is_safe() {
  local candidate="$1"
  local uid="$2"

  [[ "$candidate" == "$CODE_ROOT/"* ]] || return 1
  [[ -d "$candidate" ]] || return 1
  [[ ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  return 0
}

collect_targets() {
  local uid="$1"
  local sub candidate size_kib

  for sub in "${CACHE_SUBDIRS[@]}"; do
    candidate="$CODE_ROOT/$sub"
    if candidate_is_safe "$candidate" "$uid"; then
      size_kib="$(du -sk "$candidate" | awk '{print $1}')"
      TARGETS+=("$candidate")
      TARGET_SIZES_KIB+=("$size_kib")
    fi
  done
}

main() {
  local dry_run=0
  local uid
  local index
  local target
  local total_kib=0
  local deleted=0
  local skipped=0

  (( $# <= 1 )) || die "Too many arguments (use --help)"

  case "${1:-}" in
    "")
      ;;
    -n | --dry-run)
      dry_run=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-vscode-caches only runs on macOS."

  require_cmd awk
  require_cmd du
  require_cmd id
  require_cmd rm
  require_cmd stat

  if [[ ! -d "$CODE_ROOT" ]]; then
    echo "VS Code support directory does not exist."
    exit 0
  fi
  [[ ! -L "$CODE_ROOT" ]] || die "Refusing symlinked VS Code support directory."

  uid="$(id -u)"
  collect_targets "$uid"

  if (( ${#TARGETS[@]} == 0 )); then
    echo "No VS Code cache directories are present."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    total_kib="$((total_kib + TARGET_SIZES_KIB[$index]))"
  done

  printf 'VS Code caches: %d directories (reported %.2f GiB)\n' \
    "${#TARGETS[@]}" "$(awk -v kib="$total_kib" 'BEGIN { print kib / 1048576 }')"

  for index in "${!TARGETS[@]}"; do
    printf '  - %s (%.2f GiB)\n' \
      "${TARGETS[$index]#$CODE_ROOT/}" \
      "$(awk -v kib="${TARGET_SIZES_KIB[$index]}" 'BEGIN { print kib / 1048576 }')"
  done

  if (( dry_run )); then
    echo "Dry run: nothing was deleted."
    exit 0
  fi

  for index in "${!TARGETS[@]}"; do
    target="${TARGETS[$index]}"

    if candidate_is_safe "$target" "$uid"; then
      rm -rf -- "$target"
      deleted="$((deleted + 1))"
    else
      skipped="$((skipped + 1))"
    fi
  done

  echo "Deleted: $deleted"
  echo "Skipped after final safety check: $skipped"
}

main "$@"
