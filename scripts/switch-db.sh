#!/usr/bin/env bash
# scripts/switch-db.sh
# 1. Select a project from configs/work-state.json
# 2. Find appsettings.json in that project
# 3. Use fzf to switch the active ConnectionString

set -euo pipefail

#######################################
# Resolve paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${ROOT_DIR}/configs/work-state.json"

# Load forge environment if available
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/forge.sh"
fi

die() { echo "✖ $*" >&2; exit 1; }
command -v fzf >/dev/null 2>&1 || die "fzf missing"
command -v python3 >/dev/null 2>&1 || die "python3 missing"

[[ -f "$STATE_FILE" ]] || die "Missing state file: $STATE_FILE"

#######################################
# Pick project
#######################################
project_choice=$({
  python3 - "$STATE_FILE" <<'PY_IN'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    j = json.load(f)
projects = j.get("db-switch-projects", [])
for i, p in enumerate(projects):
    print(f"{i}:: {p.get('title','')} ({p.get('path','')})")
PY_IN
} | fzf --prompt="Select project > " --height=20% --reverse) || exit 0

proj_idx="${project_choice%%::*}"

# Get path for selected project
PROJ_PATH=$(python3 - "$STATE_FILE" "$proj_idx" <<'PY_PATH'
import json, sys
path, idx = sys.argv[1], int(sys.argv[2])
with open(path, "r", encoding="utf-8") as f:
    j = json.load(f)
print(j["db-switch-projects"][idx]["path"])
PY_PATH
)

[[ -d "$PROJ_PATH" ]] || die "Project directory not found: $PROJ_PATH"

#######################################
# Find appsettings.json
#######################################
# Search for appsettings.json in the project root or subdirectories
# Priority: root > Asms2.Web > others
APP_SETTINGS=""
if [[ -f "$PROJ_PATH/appsettings.json" ]]; then
    APP_SETTINGS="$PROJ_PATH/appsettings.json"
elif [[ -f "$PROJ_PATH/Asms2.Web/appsettings.json" ]]; then
    APP_SETTINGS="$PROJ_PATH/Asms2.Web/appsettings.json"
else
    # Fallback: search for it
    APP_SETTINGS=$(find "$PROJ_PATH" -maxdepth 3 -name "appsettings.json" | head -n 1)
fi

[[ -n "$APP_SETTINGS" ]] || die "Could not find appsettings.json in $PROJ_PATH"

echo "Using: $APP_SETTINGS"

#######################################
# Pick connection string
#######################################
selection=$(grep -n "\"ConnectionString\":" "$APP_SETTINGS" | \
    fzf -d : \
        --prompt="Switch DB > " \
        --height=40% \
        --reverse \
        --header="Select Connection String to activate (Enter to switch, Esc to cancel)" \
        --with-nth=2.. \
        --preview "awk -v ln={1} 'NR >= ln-5 && NR <= ln+5 { printf \"%3d %s %s\\n\", NR, (NR == ln ? \">\" : \" \" ), \$0 }' \"$APP_SETTINGS\"")

if [[ -z "$selection" ]]; then
    exit 0
fi

line_num=$(echo "$selection" | cut -d: -f1)

#######################################
# Switch context using Python
#######################################
python3 - "$APP_SETTINGS" "$line_num" <<'PY_SWITCH'
import sys
import re

file_path = sys.argv[1]
target_idx = int(sys.argv[2]) - 1

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

def is_commented(l):
    s = l.strip()
    return s.startswith("//") or s.startswith("#") or s.startswith("/*")

def uncomment(l):
    # Preserve indentation, remove leading // or # or /*
    res = re.sub(r'^([ \t]*)(?://|#|/\*)[ \t]*', r'\1', l)
    res = res.replace("*/", "")
    return res

def comment(l):
    if is_commented(l):
        return l
    return re.sub(r'^([ \t]*)', r'\1// ', l)

new_lines = []
target_line = lines[target_idx]
raw_target = re.search(r'("ConnectionString":\s*".*?")', target_line)

if not raw_target:
    print(f"✖ Selected line does not seem to be a ConnectionString")
    sys.exit(1)

print(f"Activating: {raw_target.group(1)}")

for i, line in enumerate(lines):
    if i == target_idx:
        new_lines.append(uncomment(line))
    elif '"ConnectionString":' in line:
        if not is_commented(line):
            new_lines.append(comment(line))
        else:
            new_lines.append(line)
    else:
        new_lines.append(line)

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("✓ Done")
PY_SWITCH
