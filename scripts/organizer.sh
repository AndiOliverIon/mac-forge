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
LOCAL_STORE_FILE="${FORGE_CONFIG_LOCAL_DIR:-$HOME/mac-forge/config-local}/local-store.json"

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
# Read organizer.retention_days from local-store
#######################################
read_retention_days() {
  if [[ ! -f "$LOCAL_STORE_FILE" ]]; then
    return 0
  fi

  python3 - "$LOCAL_STORE_FILE" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

organizer = data.get("organizer", {})
if not isinstance(organizer, dict):
    raise SystemExit(0)

days = organizer.get("retention_days")
if isinstance(days, int) and days > 0:
    print(days)
PY
}

#######################################
# List old files by access time in folders (recursive)
# Output lines: atime_iso<TAB>absolute_path
#######################################
list_old_files() {
  local retention_days="$1"
  local local_store_file="$2"
  shift
  shift

  python3 - "$retention_days" "$local_store_file" "$@" <<'PY'
import fnmatch
import json
import os
import sys
import time
from datetime import datetime

days = int(sys.argv[1])
local_store = sys.argv[2]
targets = sys.argv[3:]
cutoff = time.time() - (days * 86400)

skip_patterns = []
if local_store and os.path.isfile(local_store):
    with open(local_store, "r", encoding="utf-8") as f:
        data = json.load(f)
    organizer = data.get("organizer", {})
    if isinstance(organizer, dict):
        patterns = organizer.get("skip_patterns", [])
        if isinstance(patterns, list):
            for p in patterns:
                if isinstance(p, str):
                    p = p.strip()
                    if p:
                        skip_patterns.append(p)

rows = []
for target in targets:
    if not os.path.isdir(target):
        continue
    for root, _, files in os.walk(target):
        for name in files:
            path = os.path.join(root, name)
            abs_path = os.path.abspath(path)
            rel_path = os.path.relpath(abs_path, target)
            if any(
                fnmatch.fnmatch(name, pat)
                or fnmatch.fnmatch(rel_path, pat)
                or fnmatch.fnmatch(abs_path, pat)
                for pat in skip_patterns
            ):
                continue
            try:
                st = os.stat(path, follow_symlinks=False)
            except OSError:
                continue
            atime = st.st_atime
            if atime < cutoff:
                dt = datetime.fromtimestamp(atime).strftime("%Y-%m-%d %H:%M:%S")
                rows.append((atime, dt, abs_path))

rows.sort(key=lambda x: x[0])
for _, dt, path in rows:
    print(f"{dt}\t{path}")
PY
}

#######################################
# Delete files passed as args
#######################################
delete_files() {
  python3 - "$@" <<'PY'
import os
import sys

deleted = 0
failed = 0

for p in sys.argv[1:]:
    try:
        if os.path.isfile(p):
            os.remove(p)
            deleted += 1
    except OSError:
        failed += 1

print(f"{deleted}\t{failed}")
PY
}

#######################################
# Retention cleanup (prompted)
#######################################
run_retention_cleanup() {
  local retention_days="$1"
  shift
  local targets=("$@")

  [[ "$retention_days" =~ ^[0-9]+$ ]] || return 0
  (( retention_days > 0 )) || return 0
  (( ${#targets[@]} > 0 )) || return 0

  local old_entries=()
  mapfile -t old_entries < <(list_old_files "$retention_days" "$LOCAL_STORE_FILE" "${targets[@]}")

  if (( ${#old_entries[@]} == 0 )); then
    echo "Retention: no files older than ${retention_days} day(s) by last access time."
    return 0
  fi

  echo
  echo "Retention candidates (last access older than ${retention_days} day(s)):"

  local old_paths=()
  local entry atime path
  for entry in "${old_entries[@]}"; do
    IFS=$'\t' read -r atime path <<< "$entry"
    [[ -n "$path" ]] || continue
    old_paths+=("$path")
    echo " - $path (last access: $atime)"
  done

  (( ${#old_paths[@]} > 0 )) || return 0

  local answer
  printf "Delete these %d file(s)? (y/n): " "${#old_paths[@]}"
  read -r answer

  case "$answer" in
    y|Y)
      local result deleted failed
      result="$(delete_files "${old_paths[@]}")"
      IFS=$'\t' read -r deleted failed <<< "$result"
      echo "Retention: deleted ${deleted:-0} file(s). Failed: ${failed:-0}."
      ;;
    *)
      echo "Retention: skipped deletion."
      ;;
  esac
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

retention_days="$(read_retention_days || true)"
if [[ -n "${retention_days:-}" ]]; then
  run_retention_cleanup "$retention_days" "${targets[@]}"
else
  warn "Retention cleanup disabled (organizer.retention_days missing/invalid in local-store.json)."
fi
