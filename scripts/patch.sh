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
  $0 [--config <path>] [apply|p|-P|remove|r|-R|status|s]

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
COMMAND="${1:-apply}"
case "$COMMAND" in
  p|-P) COMMAND="apply" ;;
  r|-R) COMMAND="remove" ;;
  s)    COMMAND="status" ;;
esac

case "$COMMAND" in
  apply|remove|status) ;;
  *) usage; die "Unknown command: $COMMAND" ;;
esac

#######################################
# Parse JSON manifest into a simple stream
# Supports either:
#   - top-level list: [ {...}, {...} ]
#   - wrapper: { "interventions": [ {...} ] }
# Intervention types:
#   - Inject (default): id,file,anchor,position(before|after),lines(array)
#   - comment: id,file,comment_prefix,max_matches and either:
#       * identifier (line mode)
#       * block_start + block_end (block mode)
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

for item in items:
    if not isinstance(item, dict):
        raise SystemExit("Each intervention must be an object")

    if "id" not in item or "file" not in item:
        raise SystemExit("Each intervention must include id and file")

    t_raw = str(item.get("type", "Inject")).strip().lower()
    print(f"ID|{item['id']}")
    print(f"FILE|{item['file']}")
    print(f"TYPE|{t_raw}")

    if t_raw == "inject":
        required = {"anchor", "position", "lines"}
        missing = required - set(item.keys())
        if missing:
            raise SystemExit(f"Inject intervention missing fields {sorted(missing)}: {item['id']}")
        if item["position"] not in ("before","after"):
            raise SystemExit(f"Invalid position for {item['id']}: {item['position']} (use before/after)")
        if not isinstance(item["lines"], list):
            raise SystemExit(f"lines must be an array for {item['id']}")

        joined = "\n".join(str(x) for x in item["lines"])
        encoded = base64.b64encode(joined.encode("utf-8")).decode("utf-8")

        print(f"ANCHOR|{item['anchor']}")
        print(f"POSITION|{item['position']}")
        print(f"LINES|{encoded}")
    elif t_raw == "comment":
        prefix = str(item.get("comment_prefix", "// "))
        if prefix == "":
            raise SystemExit(f"comment_prefix must be non-empty for {item['id']}")

        max_matches = item.get("max_matches", 1)
        if not isinstance(max_matches, int) or max_matches < 1:
            raise SystemExit(f"max_matches must be an integer >= 1 for {item['id']}")

        has_identifier = "identifier" in item
        has_block = "block_start" in item or "block_end" in item

        if has_identifier and has_block:
            raise SystemExit(f"Use either identifier or block_start/block_end for {item['id']}, not both")

        if has_identifier:
            ident = str(item["identifier"])
            if ident == "":
                raise SystemExit(f"identifier must be non-empty for {item['id']}")
            print("COMMENT_MODE|line")
            print(f"IDENTIFIER|{ident}")
        else:
            if "block_start" not in item or "block_end" not in item:
                raise SystemExit(f"Comment intervention {item['id']} needs either identifier OR block_start+block_end")
            start = str(item["block_start"])
            end = str(item["block_end"])
            if start == "" or end == "":
                raise SystemExit(f"block_start/block_end must be non-empty for {item['id']}")
            print("COMMENT_MODE|block")
            print(f"BLOCK_START|{start}")
            print(f"BLOCK_END|{end}")

        print(f"COMMENT_PREFIX|{prefix}")
        print(f"MAX_MATCHES|{max_matches}")
    else:
        raise SystemExit(f"Unsupported intervention type for {item['id']}: {item.get('type')}")

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
# Comment/uncomment interventions
#######################################
comment_line_to() {
  local in="$1"
  local out="$2"
  local identifier="$3"
  local prefix="$4"
  local max_matches="$5"
  local mode="$6" # apply|remove

  awk -v ident="$identifier" -v pfx="$prefix" -v maxm="$max_matches" -v mode="$mode" '
    function apply_comment(line,   m, indent, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return line
      indent = substr(line, 1, RLENGTH)
      rest = substr(line, RLENGTH + 1)
      if (index(rest, pfx) == 1) return line
      return indent pfx rest
    }
    function remove_comment(line,  m, indent, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return line
      indent = substr(line, 1, RLENGTH)
      rest = substr(line, RLENGTH + 1)
      if (index(rest, pfx) == 1) return indent substr(rest, length(pfx) + 1)
      return line
    }
    {
      if (index($0, ident) > 0) {
        found++
        if (mode == "apply") {
          print apply_comment($0)
        } else {
          print remove_comment($0)
        }
      } else {
        print $0
      }
    }
    END {
      if (found == 0) exit 2
      if (found > maxm) exit 3
    }
  ' "$in" > "$out"
}

comment_block_to() {
  local in="$1"
  local out="$2"
  local block_start="$3"
  local block_end="$4"
  local prefix="$5"
  local max_matches="$6"
  local mode="$7" # apply|remove

  awk -v bs="$block_start" -v be="$block_end" -v pfx="$prefix" -v maxm="$max_matches" -v mode="$mode" '
    function apply_comment(line,   m, indent, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return line
      indent = substr(line, 1, RLENGTH)
      rest = substr(line, RLENGTH + 1)
      if (index(rest, pfx) == 1) return line
      return indent pfx rest
    }
    function remove_comment(line,  m, indent, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return line
      indent = substr(line, 1, RLENGTH)
      rest = substr(line, RLENGTH + 1)
      if (index(rest, pfx) == 1) return indent substr(rest, length(pfx) + 1)
      return line
    }
    {
      if (!in_block && index($0, bs) > 0) {
        in_block = 1
        blocks++
      }

      if (in_block) {
        if (mode == "apply") {
          print apply_comment($0)
        } else {
          print remove_comment($0)
        }
        if (index($0, be) > 0) in_block = 0
      } else {
        print $0
      }
    }
    END {
      if (in_block) exit 4
      if (blocks == 0) exit 2
      if (blocks > maxm) exit 3
    }
  ' "$in" > "$out"
}

comment_line_status() {
  local file="$1"
  local identifier="$2"
  local prefix="$3"
  local max_matches="$4"
  awk -v ident="$identifier" -v pfx="$prefix" -v maxm="$max_matches" '
    function is_commented(line,   m, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return 0
      rest = substr(line, RLENGTH + 1)
      return index(rest, pfx) == 1
    }
    {
      if (index($0, ident) > 0) {
        found++
        if (is_commented($0)) commented++
      }
    }
    END {
      if (found == 0) { print "missing"; exit }
      if (found > maxm) { print "invalid"; exit }
      if (commented == found) print "applied"; else if (commented == 0) print "not_applied"; else print "partial";
    }
  ' "$file"
}

comment_block_status() {
  local file="$1"
  local block_start="$2"
  local block_end="$3"
  local prefix="$4"
  local max_matches="$5"
  awk -v bs="$block_start" -v be="$block_end" -v pfx="$prefix" -v maxm="$max_matches" '
    function is_commented(line,   m, rest) {
      if (match(line, /^[[:space:]]*/) == 0) return 0
      rest = substr(line, RLENGTH + 1)
      return index(rest, pfx) == 1
    }
    {
      if (!in_block && index($0, bs) > 0) {
        in_block=1
        blocks++
      }
      if (in_block) {
        lines++
        if (is_commented($0)) commented++
        if (index($0, be) > 0) in_block=0
      }
    }
    END {
      if (in_block) { print "invalid"; exit }
      if (blocks == 0) { print "missing"; exit }
      if (blocks > maxm) { print "invalid"; exit }
      if (commented == lines) print "applied"; else if (commented == 0) print "not_applied"; else print "partial";
    }
  ' "$file"
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
declare -a IDS FILES TYPES ANCHORS POSITIONS BLOCKS
declare -a COMMENT_MODES IDENTIFIERS BLOCK_STARTS BLOCK_ENDS COMMENT_PREFIXES MAX_MATCHES

load_interventions() {
  local cur_id="" cur_file="" cur_type=""
  local cur_anchor="" cur_pos="" cur_lines_b64=""
  local cur_comment_mode="" cur_identifier="" cur_block_start="" cur_block_end=""
  local cur_comment_prefix="" cur_max_matches=""

  while IFS= read -r line; do
    case "$line" in
      ID\|*)       cur_id="${line#ID|}" ;;
      FILE\|*)     cur_file="${line#FILE|}" ;;
      TYPE\|*)     cur_type="${line#TYPE|}" ;;
      ANCHOR\|*)   cur_anchor="${line#ANCHOR|}" ;;
      POSITION\|*) cur_pos="${line#POSITION|}" ;;
      LINES\|*)    cur_lines_b64="${line#LINES|}" ;;
      COMMENT_MODE\|*)   cur_comment_mode="${line#COMMENT_MODE|}" ;;
      IDENTIFIER\|*)     cur_identifier="${line#IDENTIFIER|}" ;;
      BLOCK_START\|*)    cur_block_start="${line#BLOCK_START|}" ;;
      BLOCK_END\|*)      cur_block_end="${line#BLOCK_END|}" ;;
      COMMENT_PREFIX\|*) cur_comment_prefix="${line#COMMENT_PREFIX|}" ;;
      MAX_MATCHES\|*)    cur_max_matches="${line#MAX_MATCHES|}" ;;
      END_ITEM)
        IDS+=("$cur_id")
        FILES+=("$cur_file")
        TYPES+=("$cur_type")
        ANCHORS+=("$cur_anchor")
        POSITIONS+=("$cur_pos")
        BLOCKS+=("$cur_lines_b64")
        COMMENT_MODES+=("$cur_comment_mode")
        IDENTIFIERS+=("$cur_identifier")
        BLOCK_STARTS+=("$cur_block_start")
        BLOCK_ENDS+=("$cur_block_end")
        COMMENT_PREFIXES+=("$cur_comment_prefix")
        MAX_MATCHES+=("$cur_max_matches")
        cur_id=""; cur_file=""; cur_type=""
        cur_anchor=""; cur_pos=""; cur_lines_b64=""
        cur_comment_mode=""; cur_identifier=""; cur_block_start=""; cur_block_end=""
        cur_comment_prefix=""; cur_max_matches=""
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
  local total="${#IDS[@]}"
  local inject_total=0 comment_total=0
  local applied_count=0 not_applied_count=0 partial_count=0 missing_count=0 invalid_count=0
  local unique_targets="" pending_targets="" issue_targets=""
  local exception_lines=""
  local exception_count=0

  add_unique_line() {
    local list="$1"
    local value="$2"
    if [[ -z "$list" ]]; then
      printf '%s' "$value"
      return
    fi
    if grep -Fqx "$value" <<< "$list"; then
      printf '%s' "$list"
    else
      printf '%s\n%s' "$list" "$value"
    fi
  }

  count_lines() {
    local text="$1"
    [[ -n "$text" ]] || { echo 0; return; }
    printf '%s\n' "$text" | wc -l | tr -d ' '
  }

  for i in "${!IDS[@]}"; do
    local id="${IDS[$i]}"
    local rel="${FILES[$i]}"
    local type="${TYPES[$i]}"
    local target="$REPO_ROOT/$rel"
    local st=""

    unique_targets="$(add_unique_line "$unique_targets" "$rel")"

    [[ "$type" == "inject" ]] && ((inject_total+=1))
    [[ "$type" == "comment" ]] && ((comment_total+=1))

    if [[ ! -f "$target" ]]; then
      st="missing"
    elif [[ "$type" == "inject" ]]; then
      if block_exists "$target" "$id"; then
        st="applied"
      else
        st="not_applied"
      fi
    elif [[ "$type" == "comment" ]]; then
      local mode="${COMMENT_MODES[$i]}"
      local prefix="${COMMENT_PREFIXES[$i]}"
      local max_matches="${MAX_MATCHES[$i]}"
      if [[ "$mode" == "line" ]]; then
        st="$(comment_line_status "$target" "${IDENTIFIERS[$i]}" "$prefix" "$max_matches")"
      else
        st="$(comment_block_status "$target" "${BLOCK_STARTS[$i]}" "${BLOCK_ENDS[$i]}" "$prefix" "$max_matches")"
      fi
    else
      st="invalid"
    fi

    case "$st" in
      applied)
        ((applied_count+=1))
        ;;
      not_applied)
        ((not_applied_count+=1))
        pending_targets="$(add_unique_line "$pending_targets" "$rel")"
        ;;
      partial)
        ((partial_count+=1))
        exception_count=$((exception_count + 1))
        issue_targets="$(add_unique_line "$issue_targets" "$rel")"
        exception_lines+=$'\n'"- $id ($rel): partial"
        ;;
      missing)
        ((missing_count+=1))
        exception_count=$((exception_count + 1))
        issue_targets="$(add_unique_line "$issue_targets" "$rel")"
        exception_lines+=$'\n'"- $id ($rel): missing target/identifier/block"
        ;;
      *)
        ((invalid_count+=1))
        exception_count=$((exception_count + 1))
        issue_targets="$(add_unique_line "$issue_targets" "$rel")"
        exception_lines+=$'\n'"- $id ($rel): invalid or unsupported"
        ;;
    esac
  done

  local unique_target_count pending_target_count issue_target_count
  unique_target_count="$(count_lines "$unique_targets")"
  pending_target_count="$(count_lines "$pending_targets")"
  issue_target_count="$(count_lines "$issue_targets")"

  echo "Patch status"
  echo "Repo:   $REPO_ROOT"
  echo "Config: $CONFIG_FILE"
  echo
  echo "Interventions: $total (inject: $inject_total, comment: $comment_total)"
  echo "Target files:  $unique_target_count"
  echo
  echo "State:"
  echo "- Applied:     $applied_count"
  echo "- Pending:     $not_applied_count"
  echo "- Exceptions:  $exception_count (partial: $partial_count, missing: $missing_count, invalid: $invalid_count)"
  echo
  echo "Impact:"
  echo "- Files to touch for apply: $pending_target_count"
  echo "- Files needing attention:  $issue_target_count"

  if [[ -n "$exception_lines" ]]; then
    echo
    echo "Exceptions:"
    echo "${exception_lines#"$'\n'"}"
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
      local type="${TYPES[$i]}"
      local anchor="${ANCHORS[$i]}"
      local pos="${POSITIONS[$i]}"
      local lines_b64="${BLOCKS[$i]}"

      local target="$REPO_ROOT/$rel"
      local work="$TEMP_DIR/work.$i"

      if [[ "$type" == "inject" ]]; then
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
      elif [[ "$type" == "comment" ]]; then
        local mode="${COMMENT_MODES[$i]}"
        local prefix="${COMMENT_PREFIXES[$i]}"
        local max_matches="${MAX_MATCHES[$i]}"

        if [[ "$mode" == "line" ]]; then
          if ! comment_line_to "$target" "$work" "${IDENTIFIERS[$i]}" "$prefix" "$max_matches" "apply"; then
            case $? in
              2) die "Comment apply failed for '$id' in '$rel' (identifier not found)." ;;
              3) die "Comment apply failed for '$id' in '$rel' (matched more than max_matches=$max_matches)." ;;
              *) die "Comment apply failed for '$id' in '$rel'." ;;
            esac
          fi
        else
          if ! comment_block_to "$target" "$work" "${BLOCK_STARTS[$i]}" "${BLOCK_ENDS[$i]}" "$prefix" "$max_matches" "apply"; then
            case $? in
              2) die "Comment apply failed for '$id' in '$rel' (block_start/block_end not found)." ;;
              3) die "Comment apply failed for '$id' in '$rel' (matched more than max_matches=$max_matches)." ;;
              4) die "Comment apply failed for '$id' in '$rel' (unterminated block)." ;;
              *) die "Comment apply failed for '$id' in '$rel'." ;;
            esac
          fi
        fi
      else
        die "Unsupported intervention type '$type' for '$id'."
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
      local type="${TYPES[$i]}"

      local target="$REPO_ROOT/$rel"
      local work="$TEMP_DIR/work.$i"

      if [[ "$type" == "inject" ]]; then
        # Always attempt removal (idempotent)
        remove_block_to "$target" "$work" "$id"
      elif [[ "$type" == "comment" ]]; then
        local mode="${COMMENT_MODES[$i]}"
        local prefix="${COMMENT_PREFIXES[$i]}"
        local max_matches="${MAX_MATCHES[$i]}"

        if [[ "$mode" == "line" ]]; then
          if ! comment_line_to "$target" "$work" "${IDENTIFIERS[$i]}" "$prefix" "$max_matches" "remove"; then
            case $? in
              2) die "Comment remove failed for '$id' in '$rel' (identifier not found)." ;;
              3) die "Comment remove failed for '$id' in '$rel' (matched more than max_matches=$max_matches)." ;;
              *) die "Comment remove failed for '$id' in '$rel'." ;;
            esac
          fi
        else
          if ! comment_block_to "$target" "$work" "${BLOCK_STARTS[$i]}" "${BLOCK_ENDS[$i]}" "$prefix" "$max_matches" "remove"; then
            case $? in
              2) die "Comment remove failed for '$id' in '$rel' (block_start/block_end not found)." ;;
              3) die "Comment remove failed for '$id' in '$rel' (matched more than max_matches=$max_matches)." ;;
              4) die "Comment remove failed for '$id' in '$rel' (unterminated block)." ;;
              *) die "Comment remove failed for '$id' in '$rel'." ;;
            esac
          fi
        fi
      else
        die "Unsupported intervention type '$type' for '$id'."
      fi

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
