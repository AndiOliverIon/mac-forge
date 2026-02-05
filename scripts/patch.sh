#!/usr/bin/env bash
set -euo pipefail

TEMP_DIR=""

cleanup() {
  if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

die() { echo "❌ $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 [--config <path>] {apply|-P|remove|-R|status}

Defaults:
  - Config path: \$FORGE_CONFIG_LOCAL_DIR/local-overrides.json
  - Fallback:    \$FORGE_CONFIG_LOCAL_DIR/local-overrides.example.json

Notes:
  - Must be run inside a git repo (targets resolved from repo root).
  - Works even if your working tree is dirty.
  - On apply/remove, touched files are UNSTAGED (only those files).
EOF
}

#######################################
# Load forge config (same logic pattern you use elsewhere)
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
else
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/forge.sh"
fi

: "${FORGE_CONFIG_LOCAL_DIR:?FORGE_CONFIG_LOCAL_DIR must be set by forge.sh}"

#######################################
# Resolve repo root
#######################################
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not inside a git repository."
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"

#######################################
# Config selection
#######################################
CONFIG_FILE_DEFAULT="$FORGE_CONFIG_LOCAL_DIR/local-overrides.json"
CONFIG_FILE_EXAMPLE="$FORGE_CONFIG_LOCAL_DIR/local-overrides.example.json"
CONFIG_FILE="$CONFIG_FILE_DEFAULT"

if [[ "${1:-}" == "--config" ]]; then
  [[ -n "${2:-}" ]] || { usage; die "Missing value for --config"; }
  if [[ "$2" = /* ]]; then
    CONFIG_FILE="$2"
  else
    CONFIG_FILE="$PWD/$2"
  fi
  shift 2
else
  if [[ ! -f "$CONFIG_FILE_DEFAULT" && -f "$CONFIG_FILE_EXAMPLE" ]]; then
    CONFIG_FILE="$CONFIG_FILE_EXAMPLE"
  fi
fi

[[ -f "$CONFIG_FILE" ]] || die "Config not found. Tried: $CONFIG_FILE_DEFAULT and $CONFIG_FILE_EXAMPLE (or pass --config)."

#######################################
# Command parsing
#######################################
COMMAND="${1:-}"
[[ -n "$COMMAND" ]] || { usage; exit 1; }
[[ "$COMMAND" == "-P" ]] && COMMAND="apply"
[[ "$COMMAND" == "-R" ]] && COMMAND="remove"

case "$COMMAND" in
  apply|remove|status) ;;
  *) usage; die "Unknown command: $COMMAND" ;;
esac

#######################################
# Parse JSON manifest into a simple stream
# Supports either:
#   - top-level list: [ {...}, {...} ]
#   - wrapper: { "interventions": [ {...} ] }
#
# Required per intervention:
#   id, file, anchor, position(before|after), lines(array of strings)
#######################################
parse_manifest() {
  python3 - "$CONFIG_FILE" <<'PY'
import sys, json, base64

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

items = data["interventions"] if isinstance(data, dict) and "interventions" in data else data
if not isinstance(items, list):
    raise SystemExit("Manifest must be a list or {interventions:[...]}")

required = {"id","file","anchor","position","lines"}

for item in items:
    if not isinstance(item, dict):
        raise SystemExit("Each intervention must be an object")
    missing = required - set(item.keys())
    if missing:
        raise SystemExit(f"Intervention missing fields {sorted(missing)}: {item.get('id','<no id>')}")
    if item["position"] not in ("before","after"):
        raise SystemExit(f"Invalid position for {item['id']}: {item['position']} (use before/after)")
    if not isinstance(item["lines"], list):
        raise SystemExit(f"lines must be an array for {item['id']}")

    joined = "\n".join(str(x) for x in item["lines"])
    encoded = base64.b64encode(joined.encode("utf-8")).decode("utf-8")

    print(f"ID|{item['id']}")
    print(f"FILE|{item['file']}")
    print(f"ANCHOR|{item['anchor']}")
    print(f"POSITION|{item['position']}")
    print(f"LINES|{encoded}")
    print("END_ITEM")
PY
}

#######################################
# Marker tokens (token-based matching)
#######################################
marker_begin_token() { echo "LOCAL_OVERRIDES_BEGIN: $1"; }
marker_end_token()   { echo "LOCAL_OVERRIDES_END: $1"; }

block_exists() {
  local file="$1"
  local id="$2"
  local token
  token="$(marker_begin_token "$id")"
  grep -Fq "$token" "$file"
}

#######################################
# Validate that a decoded block contains both tokens for this id.
# (So removal is always deterministic.)
#######################################
validate_block_tokens() {
  local id="$1"
  local blockfile="$2"
  local b e
  b="$(marker_begin_token "$id")"
  e="$(marker_end_token "$id")"

  grep -Fq "$b" "$blockfile" || die "Manifest block for '$id' is missing begin token: $b"
  grep -Fq "$e" "$blockfile" || die "Manifest block for '$id' is missing end token: $e"
}

#######################################
# Remove block: delete inclusive range from BEGIN token line to END token line
#######################################
remove_block_to() {
  local in="$1"
  local out="$2"
  local id="$3"
  local b e
  b="$(marker_begin_token "$id")"
  e="$(marker_end_token "$id")"

  awk -v b="$b" -v e="$e" '
    BEGIN { skipping=0 }
    {
      if (!skipping && index($0, b) > 0) { skipping=1; next }
      if (skipping && index($0, e) > 0) { skipping=0; next }
      if (!skipping) print $0
    }
  ' "$in" > "$out"
}

#######################################
# Inject block relative to anchor using a block file (macOS awk-safe)
#######################################
inject_block_to() {
  local in="$1"
  local out="$2"
  local anchor="$3"
  local position="$4"   # before|after
  local blockfile="$5"  # file containing block lines

  grep -Fq "$anchor" "$in" || return 2

  awk -v anchor="$anchor" -v pos="$position" -v bf="$blockfile" '
    BEGIN { inserted=0 }
    {
      if (!inserted && index($0, anchor) > 0) {
        if (pos=="before") {
          while ((getline l < bf) > 0) print l
          close(bf)
          print $0
        } else {
          print $0
          while ((getline l < bf) > 0) print l
          close(bf)
        }
        inserted=1
        next
      }
      print $0
    }
    END { if (!inserted) exit 3 }
  ' "$in" > "$out"
}

#######################################
# Git helper: unstage file if staged (only the touched files)
#######################################
unstage_if_staged() {
  local rel="$1"
  if git diff --cached --name-only | grep -Fxq "$rel"; then
    git reset -q -- "$rel"
  fi
}

#######################################
# Load interventions into arrays
#######################################
declare -a IDS FILES ANCHORS POSITIONS BLOCKS

load_interventions() {
  local cur_id="" cur_file="" cur_anchor="" cur_pos="" cur_lines_b64=""

  while IFS= read -r line; do
    case "$line" in
      ID\|*)       cur_id="${line#ID|}" ;;
      FILE\|*)     cur_file="${line#FILE|}" ;;
      ANCHOR\|*)   cur_anchor="${line#ANCHOR|}" ;;
      POSITION\|*) cur_pos="${line#POSITION|}" ;;
      LINES\|*)    cur_lines_b64="${line#LINES|}" ;;
      END_ITEM)
        IDS+=("$cur_id")
        FILES+=("$cur_file")
        ANCHORS+=("$cur_anchor")
        POSITIONS+=("$cur_pos")
        BLOCKS+=("$cur_lines_b64")
        cur_id=""; cur_file=""; cur_anchor=""; cur_pos=""; cur_lines_b64=""
        ;;
      *) ;;
    esac
  done < <(parse_manifest)

  [[ "${#IDS[@]}" -gt 0 ]] || die "No interventions found in manifest."
}

#######################################
# Transaction: backup + rollback
#######################################
backup_targets() {
  local backup_dir="$1"
  mkdir -p "$backup_dir"

  for i in "${!IDS[@]}"; do
    local rel="${FILES[$i]}"
    local target="$REPO_ROOT/$rel"
    [[ -f "$target" ]] || die "Target file missing: $rel"
    mkdir -p "$backup_dir/$(dirname "$rel")"
    cp "$target" "$backup_dir/$rel"
  done
}

restore_targets() {
  local backup_dir="$1"
  # Restore backed up files
  for i in "${!IDS[@]}"; do
    local rel="${FILES[$i]}"
    local src="$backup_dir/$rel"
    local dst="$REPO_ROOT/$rel"
    if [[ -f "$src" ]]; then
      cp "$src" "$dst"
    fi
  done
}

#######################################
# status
#######################################
cmd_status() {
  load_interventions
  echo "Repo:   $REPO_ROOT"
  echo "Config: $CONFIG_FILE"
  echo

  local any_applied=0
  for i in "${!IDS[@]}"; do
    local id="${IDS[$i]}"
    local rel="${FILES[$i]}"
    local target="$REPO_ROOT/$rel"

    if [[ ! -f "$target" ]]; then
      echo "✖ $id  (missing file: $rel)"
      continue
    fi

    if block_exists "$target" "$id"; then
      echo "✔ $id  (applied) -> $rel"
      any_applied=1
    else
      echo "· $id  (not applied) -> $rel"
    fi
  done

  echo
  if [[ "$any_applied" -eq 1 ]]; then
    echo "Local overrides: APPLIED"
  else
    echo "Local overrides: NOT applied"
  fi
}

#######################################
# apply (works in dirty tree; transaction + rollback)
#######################################
cmd_apply() {
  load_interventions
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-patch.XXXXXX")"
  local backup_dir="$TEMP_DIR/backup"

  backup_targets "$backup_dir"

  # If something fails after this point, restore backups
  set +e
  (
    set -euo pipefail

    # Unstage touched files to avoid committing stale staged state
    for i in "${!IDS[@]}"; do
      unstage_if_staged "${FILES[$i]}"
    done

    for i in "${!IDS[@]}"; do
      local id="${IDS[$i]}"
      local rel="${FILES[$i]}"
      local anchor="${ANCHORS[$i]}"
      local pos="${POSITIONS[$i]}"
      local lines_b64="${BLOCKS[$i]}"

      local target="$REPO_ROOT/$rel"
      local work="$TEMP_DIR/work.$i"

      # If already applied, skip (idempotent)
      if block_exists "$target" "$id"; then
        continue
      fi

      # Build blockfile from manifest lines
      local blockfile="$TEMP_DIR/block.$i"
      python3 - <<PY > "$blockfile"
import base64
print(base64.b64decode("${lines_b64}").decode("utf-8"), end="")
PY

      validate_block_tokens "$id" "$blockfile"

      if ! inject_block_to "$target" "$work" "$anchor" "$pos" "$blockfile"; then
        die "Failed to inject '$id' into '$rel' (anchor missing or injection failed)."
      fi

      mv "$work" "$target"
    done
  )
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "⚠️ Apply failed. Restoring original files..." >&2
    restore_targets "$backup_dir"
    exit $rc
  fi

  echo "✅ Local overrides applied."
}

#######################################
# remove (works in dirty tree; transaction + rollback)
#######################################
cmd_remove() {
  load_interventions
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-patch.XXXXXX")"
  local backup_dir="$TEMP_DIR/backup"

  backup_targets "$backup_dir"

  set +e
  (
    set -euo pipefail

    # Unstage touched files to avoid committing stale staged override state
    for i in "${!IDS[@]}"; do
      unstage_if_staged "${FILES[$i]}"
    done

    for i in "${!IDS[@]}"; do
      local id="${IDS[$i]}"
      local rel="${FILES[$i]}"

      local target="$REPO_ROOT/$rel"
      local work="$TEMP_DIR/work.$i"

      # Always attempt removal (idempotent)
      remove_block_to "$target" "$work" "$id"
      mv "$work" "$target"
    done
  )
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "⚠️ Remove failed. Restoring original files..." >&2
    restore_targets "$backup_dir"
    exit $rc
  fi

  echo "✅ Local overrides removed."
}

#######################################
# dispatch
#######################################
case "$COMMAND" in
  status) cmd_status ;;
  apply)  cmd_apply ;;
  remove) cmd_remove ;;
esac
