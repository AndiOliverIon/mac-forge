#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean-uv-cache [--all] [--dry-run]

Prune unused uv cache entries. Installed Python environments and projects are
not affected. With --all, delete the entire uv cache; uv will refill it on
the next install or resolve.

Options:
  --all         Delete the whole uv cache (uv cache clean).
  -n, --dry-run Show the cache location and size without changing it.
  -h, --help    Show this help.
EOF
}

resolve_uv() {
  local candidate

  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi

  for candidate in "$HOME/.local/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

cache_dir_from_uv() {
  local uv_bin="$1"

  "$uv_bin" cache dir 2>/dev/null || true
}

default_cache_dir() {
  if [[ -n "${UV_CACHE_DIR:-}" ]]; then
    printf '%s\n' "$UV_CACHE_DIR"
  else
    printf '%s\n' "$HOME/.cache/uv"
  fi
}

tree_is_safe() {
  local candidate="$1"
  local uid="$2"

  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(stat -f '%u' "$candidate")" == "$uid" ]] || return 1

  case "$candidate" in
    "$HOME/.cache/uv" | "$HOME/.cache/uv/"*)
      return 0
      ;;
  esac

  if [[ -n "${UV_CACHE_DIR:-}" ]]; then
    [[ "$candidate" == "$UV_CACHE_DIR" || "$candidate" == "$UV_CACHE_DIR/"* ]] || return 1
    return 0
  fi

  return 1
}

main() {
  local dry_run=0
  local wipe_all=0
  local arg
  local uv_bin=""
  local cache_dir=""
  local size=""
  local uid=""

  for arg in "$@"; do
    case "$arg" in
      --all)
        wipe_all=1
        ;;
      -n | --dry-run)
        dry_run=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $arg (use --help)"
        ;;
    esac
  done

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean-uv-cache only runs on macOS."

  command -v awk >/dev/null 2>&1 || die "awk is not available."
  command -v du >/dev/null 2>&1 || die "du is not available."
  command -v stat >/dev/null 2>&1 || die "stat is not available."
  command -v rm >/dev/null 2>&1 || die "rm is not available."
  command -v id >/dev/null 2>&1 || die "id is not available."

  uv_bin="$(resolve_uv || true)"
  if [[ -n "$uv_bin" ]]; then
    cache_dir="$(cache_dir_from_uv "$uv_bin")"
  fi
  if [[ -z "$cache_dir" ]]; then
    cache_dir="$(default_cache_dir)"
  fi

  if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
    echo "uv cache directory does not exist."
    exit 0
  fi

  uid="$(id -u)"
  tree_is_safe "$cache_dir" "$uid" || die "Refusing unexpected uv cache path: $cache_dir"

  size="$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')"

  if (( wipe_all )); then
    echo "uv cache (full): $cache_dir ($size)"
    if (( dry_run )); then
      if [[ -n "$uv_bin" ]]; then
        echo "Action: uv cache clean"
      else
        echo "Action: delete $cache_dir (uv is not installed)"
      fi
      echo "Dry run: nothing was deleted."
      exit 0
    fi
    if [[ -n "$uv_bin" ]]; then
      echo "Clearing the entire uv cache..."
      "$uv_bin" cache clean
    else
      echo "uv is not installed; deleting the cache directory."
      rm -rf -- "$cache_dir"
    fi
    echo "✓ uv cache cleared."
    exit 0
  fi

  echo "uv cache (unused prune): $cache_dir ($size)"
  if [[ -z "$uv_bin" ]]; then
    echo "uv is not installed; unused-entry prune skipped."
    echo "Use the full-only uv cleaner to delete the whole cache."
    exit 0
  fi

  if (( dry_run )); then
    echo "Action: uv cache prune"
    echo "Dry run: nothing was pruned."
    exit 0
  fi

  echo "Pruning unused uv cache entries..."
  "$uv_bin" cache prune
  echo "✓ uv cache pruned."
}

main "$@"
