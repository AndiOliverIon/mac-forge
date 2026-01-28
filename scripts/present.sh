#!/usr/bin/env bash
set -euo pipefail

# Override if desired:
#   PRESENT_RES=1920x1080 present.sh
PRESENT_RES="${PRESENT_RES:-2560x1440}"

STATE_DIR="${HOME}/.cache/present-sh"
STATE_FILE="${STATE_DIR}/revert_displayplacer_cmd.txt"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' not found."; exit 1; }
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0")        Pick a display (fzf) and switch it to presentation resolution
  $(basename "$0") --r    Revert to the previous display configuration

Env:
  PRESENT_RES=2560x1440   Presentation resolution (default: 2560x1440)
EOF
}

need_cmd displayplacer
need_cmd python3
need_cmd fzf
mkdir -p "${STATE_DIR}"

current_cmd="$(displayplacer list | awk '/^displayplacer /{print; exit}')"
if [[ -z "${current_cmd}" ]]; then
  echo "Error: Could not read current displayplacer command from 'displayplacer list'."
  exit 1
fi

revert() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "Error: No saved state found to revert."
    echo "Tip: run '$(basename "$0")' once first, then revert with --r."
    exit 1
  fi

  saved_cmd="$(cat "${STATE_FILE}")"
  if [[ -z "${saved_cmd}" ]]; then
    echo "Error: Saved state file is empty: ${STATE_FILE}"
    exit 1
  fi

  echo "Reverting display configuration..."
  bash -lc "$saved_cmd"
  echo "Done."
}

present() {
  # Save current state for revert (overwrite each time).
  echo "${current_cmd}" > "${STATE_FILE}"

  # Build an fzf menu from `displayplacer list` blocks.
  # We'll try to extract a human-ish name if present; otherwise we'll show id + current mode.
  selection="$(
    python3 - <<'PY' | fzf --prompt="Select display to downshift → " --height=40% --reverse
import re, subprocess, sys

txt = subprocess.check_output(["displayplacer", "list"], text=True, errors="replace")

# Split into blocks per display using "Persistent screen id:"
# Many versions print blocks like:
# Persistent screen id: XXXXX
# Contextual screen id: ...
# Type: external
# Resolution: 3840x2160
# ...
blocks = re.split(r'(?=Persistent screen id:\s*)', txt)
items = []

def pick_first(patterns, block):
    for pat in patterns:
        m = re.search(pat, block, re.MULTILINE)
        if m:
            return m.group(1).strip()
    return ""

for b in blocks:
    m = re.search(r'Persistent screen id:\s*([0-9A-Fa-f-]+)', b)
    if not m:
        continue
    pid = m.group(1)

    # Name fields vary by version; try a few likely ones.
    name = pick_first([
        r'^\s*Display name:\s*(.+)$',
        r'^\s*Screen name:\s*(.+)$',
        r'^\s*Name:\s*(.+)$',
        r'^\s*Model:\s*(.+)$',
    ], b)

    typ  = pick_first([r'^\s*Type:\s*(.+)$'], b)
    res  = pick_first([r'^\s*Resolution:\s*(\d+x\d+)$'], b)
    hz   = pick_first([r'^\s*Hertz:\s*(.+)$', r'^\s*Hz:\s*(.+)$'], b)
    org  = pick_first([r'^\s*Origin:\s*(.+)$'], b)
    deg  = pick_first([r'^\s*Rotation:\s*(.+)$', r'^\s*Degree:\s*(.+)$'], b)

    label_parts = []
    if name:
        label_parts.append(name)
    else:
        label_parts.append("Display")

    if typ:
        label_parts.append(f"[{typ}]")
    if res:
        label_parts.append(res)
    if hz:
        label_parts.append(f"{hz}Hz" if hz.isdigit() else hz)
    if org:
        label_parts.append(f"origin:{org}")
    if deg:
        label_parts.append(f"rot:{deg}")

    label = " ".join(label_parts)
    # Print: label \t pid  (fzf shows label; we still can recover pid)
    print(f"{label}\t{pid}")
PY
  )"

  if [[ -z "${selection}" ]]; then
    echo "No selection made. Nothing changed."
    exit 0
  fi

  chosen_id="$(awk -F'\t' '{print $NF}' <<< "$selection" | tr -d '[:space:]')"
  if [[ -z "${chosen_id}" ]]; then
    echo "Error: Could not parse chosen display id."
    exit 1
  fi

  new_cmd="$(
    python3 - "$current_cmd" "$PRESENT_RES" "$chosen_id" <<'PY'
import re, sys

cmd = sys.argv[1]
present_res = sys.argv[2]
sid = sys.argv[3]

# Replace res:WxH only inside the quoted segment that contains id:<sid>
segments = re.findall(r'"[^"]*"', cmd)
if not segments:
    raise SystemExit("Error: Could not find any quoted display segments in command.")

changed = False
new_segments = []
for seg in segments:
    if f"id:{sid}" in seg:
        seg2 = re.sub(r"\bres:\d+x\d+\b", f"res:{present_res}", seg)
        changed = (seg2 != seg)
        new_segments.append(seg2)
    else:
        new_segments.append(seg)

# Rebuild the command by replacing segments in order
it = iter(new_segments)
def repl(_m): return next(it)
cmd2 = re.sub(r'"[^"]*"', repl, cmd)

if not changed:
    # Could already be at target res, or the segment might not include a res: field (rare).
    # Still output cmd2 (safe).
    pass

print(cmd2)
PY
  )"

  echo "Switching display ${chosen_id} to presentation mode: ${PRESENT_RES} ..."
  bash -lc "$new_cmd"
  echo "Done."
  echo "To revert: $(basename "$0") --r"
}

if [[ "${1:-}" == "--r" ]]; then
  revert
elif [[ "${1:-}" == "" ]]; then
  present
else
  usage
  exit 2
fi
