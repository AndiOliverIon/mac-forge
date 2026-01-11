#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/configs"
STATE_FILE="${CONFIG_DIR}/work-state.json"

die() { echo "✗ $*" >&2; exit 1; }
command -v fzf >/dev/null 2>&1 || die "fzf missing"
command -v python3 >/dev/null 2>&1 || die "python3 missing"

[[ -f "$STATE_FILE" ]] || die "Missing state file: $STATE_FILE"

choice="$({
  python3 - "$STATE_FILE" <<'PY_IN'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    j = json.load(f)
for i, l in enumerate(j.get("docker-locations", [])):
    print(f"{i}:: {l.get('title','')}")
PY_IN
} | fzf --prompt="Select work environment > ")" || exit 1

idx="${choice%%::*}"

python3 - "$STATE_FILE" "$idx" <<'PY_OUT'
import json, sys
path, idx = sys.argv[1], int(sys.argv[2])
with open(path, "r", encoding="utf-8") as f:
    j = json.load(f)
loc = j["docker-locations"][idx]
j["docker-path"] = loc["path"]
j["docker-snapshot-path"] = loc["snapshot-path"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(j, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("✓ docker-path:", j["docker-path"])
print("✓ docker-snapshot-path:", j["docker-snapshot-path"])
PY_OUT
