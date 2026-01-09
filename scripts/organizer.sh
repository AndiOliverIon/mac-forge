#!/usr/bin/env bash
set -euo pipefail

#######################################
# Load forge config (same logic as db-restore)
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
else
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/forge.sh"
fi

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

: "${FORGE_WORK_STATE_FILE:?FORGE_WORK_STATE_FILE must be set by forge.sh}"
STATE_FILE="$FORGE_WORK_STATE_FILE"
[[ -f "$STATE_FILE" ]] || die "work-state.json not found at: $STATE_FILE"

command -v python3 >/dev/null 2>&1 || die "python3 is required."

#######################################
# Read organize-categories -> lines: folder<TAB>ext1,ext2
#######################################
read_categories() {
  python3 - "$STATE_FILE" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

cats = data.get("organize-categories", [])
if not isinstance(cats, list):
    raise SystemExit("organize-categories must be an array")

for c in cats:
    if not isinstance(c, dict):
        continue
    folder = c.get("folder")
    exts = c.get("extensions", [])
    if not isinstance(folder, str) or not folder.strip():
        continue
    if not isinstance(exts, list):
        continue

    folder = folder.strip()
    clean = []
    for e in exts:
        if not isinstance(e, str):
            continue
        e = e.strip().lower()
        if e.startswith("."):
            e = e[1:]
        if e:
            clean.append(e)

    if clean:
        print(f"{folder}\t{','.join(clean)}")
PY
}

#######################################
# Read organize-folders -> one folder per line (expanded)
#######################################
read_target_folders() {
  python3 - "$STATE_FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

folders = data.get("organize-folders", [])
if folders is None:
    folders = []
if not isinstance(folders, list):
    raise SystemExit("organize-folders must be an array")

for p in folders:
    if not isinstance(p, str):
        continue
    p = p.strip()
    if not p:
        continue
    p = os.path.expandvars(os.path.expanduser(p))
    # Normalize without requiring existence
    print(os.path.abspath(p))
PY
}

#######################################
# Build ext -> category-folder map
#######################################
declare -A EXT_TO_FOLDER=()
while IFS=$'\t' read -r folder extcsv; do
  IFS=',' read -ra exts <<< "$extcsv"
  for e in "${exts[@]}"; do
    EXT_TO_FOLDER["$e"]="$folder"
  done
done < <(read_categories)

[[ "${#EXT_TO_FOLDER[@]}" -gt 0 ]] || die "No valid organize-categories found in: $STATE_FILE"

#######################################
# Move safely (avoid overwrite by suffixing -1, -2, ...)
#######################################
move_safely() {
  local src="$1"
  local dest_dir="$2"
  local name base ext candidate n

  name="$(basename -- "$src")"
  base="${name%.*}"
  ext="${name##*.}"

  mkdir -p -- "$dest_dir"

  candidate="${dest_dir}/${name}"
  if [[ ! -e "$candidate" ]]; then
    mv -- "$src" "$candidate"
    return 0
  fi

  n=1
  while :; do
    candidate="${dest_dir}/${base}-${n}.${ext}"
    if [[ ! -e "$candidate" ]]; then
      mv -- "$src" "$candidate"
      return 0
    fi
    n=$((n+1))
  done
}

#######################################
# Organize a single folder (NON-recursive)
#######################################
organize_folder() {
  local target_dir="$1"

  if [[ ! -d "$target_dir" ]]; then
    warn "Skipping (not a directory): $target_dir"
    return 0
  fi

  shopt -s nullglob
  local moved=0

  for f in "$target_dir"/*; do
    [[ -f "$f" ]] || continue

    local bn ext dest_sub
    bn="$(basename -- "$f")"

    # Skip hidden dotfiles
    [[ "$bn" == .* ]] && continue

    # Skip files without extensions
    [[ "$bn" == *.* ]] || continue

    ext="${bn##*.}"
    ext="${ext,,}" # lowercase

    dest_sub="${EXT_TO_FOLDER[$ext]:-}"
    if [[ -n "$dest_sub" ]]; then
      move_safely "$f" "$target_dir/$dest_sub"
      moved=$((moved+1))
    fi
  done

  echo "OK: $target_dir -> moved $moved file(s)"
}

#######################################
# MAIN: ONLY organize folders listed in organize-folders
#######################################
targets=()
while IFS= read -r line; do
  [[ -n "$line" ]] && targets+=("$line")
done < <(read_target_folders)

[[ "${#targets[@]}" -gt 0 ]] || die "No organize-folders configured in: $STATE_FILE"

total=0
for d in "${targets[@]}"; do
  organize_folder "$d"
  total=$((total+1))
done

echo "Done. Processed ${total} folder(s) from organize-folders."
