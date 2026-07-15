#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd -P)"
INCLUDE_NODE_MODULES=0
ASSUME_YES=0
DRY_RUN=0
TARGETS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: dotnet-clean.sh [options]

Clean generated build output and caches below the current directory.

Default directories:
  bin, obj, dist, coverage, TestResults, storybook-static,
  .angular/cache, .cache, .next, .nuxt, .output, .parcel-cache,
  .sass-cache, .svelte-kit, .turbo, .vite, and .nyc_output

Options:
  --node_modules, --node-modules  Also remove node_modules directories.
  --dry-run                       List targets without removing them.
  -y, --yes                       Skip the confirmation prompt.
  -h, --help                      Show this help.

Version-control metadata is always excluded. node_modules trees are not
entered or removed unless explicitly included.
USAGE
}

safe_root_or_die() {
  case "$ROOT_DIR" in
    /|/System|/Library|/Applications|/Users|/Volumes|/bin|/sbin|/usr|"$HOME")
      die "Refusing to clean unsafe path: $ROOT_DIR"
      ;;
  esac
}

collect_default_targets() {
  local target

  while IFS= read -r -d '' target; do
    TARGETS+=("$target")
  done < <(
    find "$ROOT_DIR" -mindepth 1 \
      \( -type d \( -name .git -o -name .hg -o -name .svn \) -prune \) -o \
      \( -type d -name node_modules -prune \) -o \
      \( -type d \( \
        -name bin -o \
        -name obj -o \
        -name dist -o \
        -name coverage -o \
        -name TestResults -o \
        -name storybook-static -o \
        -name .cache -o \
        -name .next -o \
        -name .nuxt -o \
        -name .output -o \
        -name .parcel-cache -o \
        -name .sass-cache -o \
        -name .svelte-kit -o \
        -name .turbo -o \
        -name .vite -o \
        -name .nyc_output -o \
        \( -name cache -path '*/.angular/cache' \) \
      \) -prune -print0 \)
  )
}

collect_node_modules_targets() {
  local target

  while IFS= read -r -d '' target; do
    TARGETS+=("$target")
  done < <(
    find "$ROOT_DIR" -mindepth 1 \
      \( -type d \( -name .git -o -name .hg -o -name .svn \) -prune \) -o \
      \( -type d \( \
        -name bin -o \
        -name obj -o \
        -name dist -o \
        -name coverage -o \
        -name TestResults -o \
        -name storybook-static -o \
        -name .cache -o \
        -name .next -o \
        -name .nuxt -o \
        -name .output -o \
        -name .parcel-cache -o \
        -name .sass-cache -o \
        -name .svelte-kit -o \
        -name .turbo -o \
        -name .vite -o \
        -name .nyc_output -o \
        \( -name cache -path '*/.angular/cache' \) \
      \) -prune \) -o \
      \( -type d -name node_modules -prune -print0 \)
  )
}

while (( $# > 0 )); do
  case "$1" in
    --node_modules|--node-modules)
      INCLUDE_NODE_MODULES=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -y|--yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
  shift
done

safe_root_or_die
collect_default_targets

if (( INCLUDE_NODE_MODULES == 1 )); then
  collect_node_modules_targets
fi

echo "Clean root: $ROOT_DIR"
if (( INCLUDE_NODE_MODULES == 1 )); then
  echo "node_modules: included"
else
  echo "node_modules: excluded"
fi
echo

if (( ${#TARGETS[@]} == 0 )); then
  echo "Nothing to clean."
  exit 0
fi

echo "Directories to remove (${#TARGETS[@]}):"
for target in "${TARGETS[@]}"; do
  echo "  - ${target#"$ROOT_DIR"/}"
done

if (( DRY_RUN == 1 )); then
  echo
  echo "Dry run complete; nothing was removed."
  exit 0
fi

if (( ASSUME_YES == 0 )); then
  [[ -t 0 ]] || die "Confirmation requires a terminal; use --yes for non-interactive cleanup"
  echo
  read -r -p "Remove these directories? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES|Yes)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

removed=0
for target in "${TARGETS[@]}"; do
  [[ -e "$target" ]] || continue
  rm -rf -- "$target"
  echo "Removed: ${target#"$ROOT_DIR"/}"
  removed=$((removed + 1))
done

echo
if (( removed == 1 )); then
  echo "Removed 1 directory."
else
  echo "Removed $removed directories."
fi
