#!/usr/bin/env bash
set -euo pipefail

# Local mock license chapter editor.
#   p --custom     edit amounts with fzf, write on DONE
#   p              snapshots the current list as original (once)
#   pr             restores the original list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
fi

die() { echo "❌ $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 [--old] [--edit|--snapshot|--restore]

Edit local mock license chapter amounts with fzf, then write them when Done
is selected. Run from an Ardis Perform git repo.

Notes:
  - Working file:  wwwroot/license/offline/currentModuleRestrictionList.json
  - Original file: wwwroot/license/offline/currentModuleRestrictionList.original.json
  - --snapshot copies the current working list to original if original is missing
  - --restore copies original over the working file
  - Restart Perform after writing; the mock loads this file at startup
  - --old uses Asms2.Web paths
EOF
}

USE_OLD=0
MODE="edit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --old)
      USE_OLD=1
      shift
      ;;
    --edit)
      MODE="edit"
      shift
      ;;
    --snapshot)
      MODE="snapshot"
      shift
      ;;
    --restore)
      MODE="restore"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 || die "python3 is required."
if [[ "$MODE" == "edit" ]]; then
  command -v fzf >/dev/null 2>&1 || die "fzf is required."
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not inside a git repository."
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"

if [[ "$USE_OLD" -eq 1 ]]; then
  WEB_DIR="Asms2.Web"
else
  if [[ -d "$REPO_ROOT/Ardis.Perform" ]]; then
    WEB_DIR="Ardis.Perform"
  elif [[ -d "$REPO_ROOT/Asms2.Web" ]]; then
    WEB_DIR="Asms2.Web"
  else
    WEB_DIR=""
  fi
fi

if [[ -z "$WEB_DIR" ]]; then
  if [[ "$MODE" == "edit" ]]; then
    die "Could not find Ardis.Perform or Asms2.Web under $REPO_ROOT"
  fi
  echo "No Perform web project in this repo; skipping license chapters."
  exit 0
fi

JSON_DIR="$REPO_ROOT/$WEB_DIR/wwwroot/license/offline"
JSON_PATH="$JSON_DIR/currentModuleRestrictionList.json"
ORIGINAL_PATH="$JSON_DIR/currentModuleRestrictionList.original.json"
LICENSE_CS=""
for candidate in \
  "$REPO_ROOT/Ardis.WS.Shared/Constants/License.cs" \
  "$REPO_ROOT/Ardis.WS.Shared/License.cs"
do
  if [[ -f "$candidate" ]]; then
    LICENSE_CS="$candidate"
    break
  fi
done

MOCK_APPLIED=0
if grep -Fq "LOCAL_OVERRIDES_BEGIN: local-startup-overrides" "$REPO_ROOT/$WEB_DIR/Startup.cs" 2>/dev/null; then
  MOCK_APPLIED=1
fi

snapshot_original() {
  mkdir -p "$JSON_DIR"
  if [[ -f "$ORIGINAL_PATH" ]]; then
    echo "Original chapter list already saved: $ORIGINAL_PATH"
    return 0
  fi
  if [[ -f "$JSON_PATH" ]]; then
    cp "$JSON_PATH" "$ORIGINAL_PATH"
    echo "Saved original chapter list: $ORIGINAL_PATH"
    return 0
  fi
  [[ -n "$LICENSE_CS" ]] || die "Could not find License.cs under $REPO_ROOT"
  python3 - "$LICENSE_CS" "$ORIGINAL_PATH" <<'PY'
import json
import re
import sys
from pathlib import Path

license_cs, dest = Path(sys.argv[1]), Path(sys.argv[2])
text = license_cs.read_text(encoding="utf-8-sig")
names = []
for match in re.finditer(
    r'public const string\s+(PERF_|PLAN_)[A-Za-z0-9_]+\s*=\s*(?:"([^"]+)"|nameof\(([A-Za-z0-9_]+)\))',
    text,
):
    names.append(match.group(2) or match.group(3))
out = [{"ModuleId": name, "Amount": 0} for name in sorted(set(names), key=str.lower)]
dest.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
PY
  echo "Saved original chapter list from License.cs defaults: $ORIGINAL_PATH"
}

restore_original() {
  if [[ ! -f "$ORIGINAL_PATH" ]]; then
    echo "No original chapter list to restore ($ORIGINAL_PATH)."
    return 0
  fi
  mkdir -p "$JSON_DIR"
  cp "$ORIGINAL_PATH" "$JSON_PATH"
  echo "✅ Restored original chapter list to $JSON_PATH"
  echo "Restart Perform so the mock reloads the file."
}

if [[ "$MODE" == "snapshot" ]]; then
  snapshot_original
  exit 0
fi

if [[ "$MODE" == "restore" ]]; then
  restore_original
  exit 0
fi

[[ -n "$LICENSE_CS" ]] || die "Could not find License.cs under $REPO_ROOT"
snapshot_original

STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/license-chapters.XXXXXX.json")"
cleanup() { rm -f "$STATE_FILE"; }
trap cleanup EXIT

python3 - "$LICENSE_CS" "$JSON_PATH" "$STATE_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

license_cs, json_path, state_path = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(license_cs).read_text(encoding="utf-8-sig")
names = set()
for match in re.finditer(
    r'public const string\s+(PERF_|PLAN_)[A-Za-z0-9_]+\s*=\s*(?:"([^"]+)"|nameof\(([A-Za-z0-9_]+)\))',
    text,
):
    names.add(match.group(2) or match.group(3))

current = {}
records = []
src = Path(json_path)
if src.is_file():
    raw = json.loads(src.read_text(encoding="utf-8") or "[]")
    if isinstance(raw, list):
        records = raw
        for item in raw:
            if not isinstance(item, dict):
                continue
            module_id = item.get("ModuleId")
            if not module_id:
                continue
            amount = item.get("Amount")
            current[str(module_id)] = 0 if amount is None else int(amount)

for name in names:
    current.setdefault(name, 0)

Path(state_path).write_text(
    json.dumps({"current": current, "records": records}, indent=2),
    encoding="utf-8",
)
PY

chapter_menu() {
  python3 - "$STATE_FILE" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
current = state["current"]
pending = state.get("pending", {})
dirty = 0
rows = []
for name in sorted(current, key=str.lower):
    original = int(current[name])
    amount = int(pending[name]) if name in pending else original
    if amount != original:
        dirty += 1
        shown = f"{original} → {amount}"
        mark = "*"
    else:
        shown = str(amount)
        mark = " "
    rows.append(f"{mark}\t{name}\t{shown}")

print(f"DONE\tapply {dirty} change(s)")
print("\n".join(rows))
PY
}

set_pending() {
  python3 - "$STATE_FILE" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

path, module_id, amount = sys.argv[1], sys.argv[2], int(sys.argv[3])
state = json.loads(Path(path).read_text(encoding="utf-8"))
pending = state.setdefault("pending", {})
original = int(state["current"].get(module_id, 0))
if amount == original:
    pending.pop(module_id, None)
else:
    pending[module_id] = amount
Path(path).write_text(json.dumps(state, indent=2), encoding="utf-8")
PY
}

write_json() {
  python3 - "$STATE_FILE" "$JSON_PATH" <<'PY'
import json
import sys
from pathlib import Path

state_path, json_path = sys.argv[1], sys.argv[2]
state = json.loads(Path(state_path).read_text(encoding="utf-8"))
current = dict(state["current"])
pending = state.get("pending", {})
current.update({name: int(amount) for name, amount in pending.items()})

by_id = {}
for item in state.get("records", []):
    if isinstance(item, dict) and item.get("ModuleId"):
        by_id[str(item["ModuleId"])] = dict(item)

out = []
for name in sorted(current, key=str.lower):
    record = by_id.get(name, {"ModuleId": name})
    record["ModuleId"] = name
    record["Amount"] = int(current[name])
    out.append(record)

dest = Path(json_path)
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
print(len(pending))
PY
}

pick_amount() {
  local module_id="$1"
  local current_amount="$2"
  local options=()
  options+=("0	off")
  options+=("1	on")
  if [[ "$current_amount" != "0" && "$current_amount" != "1" ]]; then
    options+=("$current_amount	keep current")
  fi
  options+=("10	")
  options+=("100	")
  options+=("CUSTOM	type a number")

  local selected
  selected="$(printf '%s\n' "${options[@]}" | fzf \
    --prompt="$module_id amount > " \
    --header="Current: $current_amount" \
    --height=40% \
    --reverse \
    --delimiter=$'\t' \
    --with-nth=1,2)" || return 1

  local choice="${selected%%$'\t'*}"
  if [[ "$choice" == "CUSTOM" ]]; then
    local typed=""
    printf "Amount for %s [%s]: " "$module_id" "$current_amount" >/dev/tty
    IFS= read -r typed </dev/tty || return 1
    typed="${typed//[[:space:]]/}"
    [[ -n "$typed" ]] || typed="$current_amount"
    [[ "$typed" =~ ^[0-9]+$ ]] || {
      echo "Not an integer: $typed" >/dev/tty
      return 1
    }
    printf '%s\n' "$typed"
    return 0
  fi
  printf '%s\n' "$choice"
}

echo "Local mock license chapters"
echo "Repo: $REPO_ROOT"
echo "Working:  $JSON_PATH"
echo "Original: $ORIGINAL_PATH"
if [[ "$MOCK_APPLIED" -eq 1 ]]; then
  echo "Bypass: applied"
else
  echo "Bypass: not applied (run p first so the mock reads this file)"
fi
echo

while true; do
  local_menu="$(chapter_menu)"
  selected="$(printf '%s\n' "$local_menu" | fzf \
    --prompt="chapter > " \
    --header="Enter edits a chapter. Select DONE to write. Esc cancels. pr restores original." \
    --height=80% \
    --reverse \
    --delimiter=$'\t' \
    --with-nth=1,2,3)" || {
    echo "Cancelled. No changes written."
    exit 0
  }

  if [[ "$selected" == DONE$'\t'* || "$selected" == DONE* ]]; then
    break
  fi

  module_id="$(printf '%s\n' "$selected" | awk -F '\t' '{print $2}')"
  shown="$(printf '%s\n' "$selected" | awk -F '\t' '{print $3}')"
  current_amount="${shown##* }"
  current_amount="${current_amount##*→ }"
  [[ -n "$module_id" ]] || continue

  amount="$(pick_amount "$module_id" "$current_amount")" || continue
  set_pending "$module_id" "$amount"
done

changed="$(write_json)"
if [[ "$changed" == "0" ]]; then
  echo "No chapter amounts changed."
  exit 0
fi

echo "✅ Wrote $changed chapter change(s) to $JSON_PATH"
echo "Restart Perform so the mock reloads the file."
echo "Run pr to restore the original chapter list."
if [[ "$MOCK_APPLIED" -eq 0 ]]; then
  echo "Local bypass is not applied; run p before starting Perform."
fi
