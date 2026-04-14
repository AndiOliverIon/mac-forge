#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
else
  echo "Missing forge runtime: $SCRIPT_DIR/forge.sh" >&2
  exit 1
fi

die() {
  echo "✗ $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 missing"
}

safe_target_or_die() {
  local path="$1"

  [[ -n "$path" ]] || die "Empty path is not allowed"
  [[ -d "$path" ]] || die "Target directory does not exist: $path"
  [[ ! -L "$path" ]] || die "Refusing to clean symlinked directory: $path"

  case "$path" in
    /|/System|/Library|/Applications|/Users|/Volumes|"$HOME")
      die "Refusing to clean unsafe path: $path"
      ;;
  esac
}

build_options() {
  python3 - "$FORGE_WORK_STATE_FILE" <<'PY'
import json, os, sys

state_file = sys.argv[1]

with open(state_file, "r", encoding="utf-8") as handle:
    state = json.load(handle)

entries = state.get("clean")
if not isinstance(entries, list):
    sys.exit(0)

for index, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    name = (
        entry.get("friendly name")
        or entry.get("friendly-name")
        or entry.get("title")
        or entry.get("name")
        or f"entry-{index + 1}"
    )
    path = str(entry.get("path") or "").strip()
    if not path:
        continue
    expanded = os.path.abspath(os.path.expanduser(path))
    print(f"{index}\t{name}\t{expanded}")
PY
}

main() {
  local selection
  local names=()
  local paths=()
  local index
  local name
  local path
  local item_count
  local failed=0

  require_cmd fzf
  require_cmd python3
  require_cmd find
  require_cmd rm

  [[ -f "$FORGE_WORK_STATE_FILE" ]] || die "Missing state file: $FORGE_WORK_STATE_FILE"

  selection="$(
    build_options | fzf \
      --multi \
      --delimiter=$'\t' \
      --with-nth=2,3 \
      --height=60% \
      --border \
      --prompt='clean > ' \
      --header='Tab: toggle, Enter: confirm selection'
  )" || exit 0

  [[ -n "$selection" ]] || exit 0

  while IFS=$'\t' read -r index name path; do
    [[ -n "$path" ]] || continue
    safe_target_or_die "$path"
    names+=("$name")
    paths+=("$path")
  done <<< "$selection"

  (( ${#paths[@]} > 0 )) || exit 0

  echo "Selected clean targets:"
  for index in "${!paths[@]}"; do
    printf '  - %s -> %s\n' "${names[$index]}" "${paths[$index]}"
  done
  echo

  for index in "${!paths[@]}"; do
    path="${paths[$index]}"
    item_count="$(find "$path" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    echo "Cleaning: ${names[$index]} -> $path ($item_count item(s))"

    if find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; then
      echo "✓ Cleaned: ${names[$index]}"
    else
      echo "✗ Failed: ${names[$index]} -> $path" >&2
      failed=1
    fi
  done

  (( failed == 0 )) || exit 1
  echo "Clean completed."
}

main "$@"
