#!/usr/bin/env bash

set -euo pipefail

# Interactive display switcher for macOS (displayplacer).
# Presents an fzf menu: All / Laptop only / Extended only.
# macOS counterpart of linux/scripts/disp.sh (kscreen-doctor).

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found. Install with: brew install $1"
}

require_cmd displayplacer
require_cmd fzf

raw="$(displayplacer list)"

# Map each persistent screen id to internal panel (1) vs external display (0).
declare -A IS_INTERNAL
cur_id=""
while IFS= read -r line; do
  case "$line" in
    "Persistent screen id: "*)
      cur_id="${line#Persistent screen id: }"
      ;;
    "Type: "*)
      [[ -z "$cur_id" ]] && continue
      if [[ "$line" == *"built in"* ]]; then
        IS_INTERNAL["$cur_id"]=1
      else
        IS_INTERNAL["$cur_id"]=0
      fi
      ;;
  esac
done <<<"$raw"

# displayplacer prints the current arrangement as a ready-to-run command; use it
# as the baseline and only flip each screen's enabled flag.
cmd_line="$(printf '%s\n' "$raw" | grep -E '^displayplacer ' | tail -n1)"
[[ -n "$cmd_line" ]] || die "Could not read current arrangement from 'displayplacer list'."

segments=()
while IFS= read -r seg; do
  [[ -n "$seg" ]] && segments+=("$seg")
done < <(printf '%s\n' "$cmd_line" | grep -oE '"[^"]*"' | sed 's/^"//; s/"$//')

((${#segments[@]} > 0)) || die "No display segments parsed from displayplacer."

seg_id() { grep -oE 'id:[^ ]+' <<<"$1" | head -n1 | cut -d: -f2-; }

set_enabled() {
  local seg="$1" val="$2"
  if [[ "$seg" == *"enabled:"* ]]; then
    sed -E "s/enabled:(true|false)/enabled:$val/" <<<"$seg"
  else
    printf '%s enabled:%s' "$seg" "$val"
  fi
}

# Tally internal/external so we can reject impossible layouts early.
n_internal=0
n_external=0
for seg in "${segments[@]}"; do
  id="$(seg_id "$seg")"
  if [[ "${IS_INTERNAL[$id]:-0}" == 1 ]]; then
    ((n_internal++))
  else
    ((n_external++))
  fi
done

choice="$(printf '%s\n' 'All' 'Laptop only' 'Extended only' \
  | fzf --prompt='Display layout > ' --height=40% --reverse)"

[[ -n "$choice" ]] || { echo "Cancelled."; exit 0; }

case "$choice" in
  'Laptop only')  ((n_internal > 0)) || die "No internal panel detected." ;;
  'Extended only') ((n_external > 0)) || die "No external display detected." ;;
esac

new_args=()
enabled_names=()
for seg in "${segments[@]}"; do
  id="$(seg_id "$seg")"
  internal="${IS_INTERNAL[$id]:-0}"
  case "$choice" in
    'All')           val=true ;;
    'Laptop only')   [[ "$internal" == 1 ]] && val=true || val=false ;;
    'Extended only') [[ "$internal" == 1 ]] && val=false || val=true ;;
    *) die "Unknown choice: $choice" ;;
  esac
  new_args+=("$(set_enabled "$seg" "$val")")
  [[ "$val" == true ]] && enabled_names+=("$id")
done

((${#enabled_names[@]} > 0)) || die "Refusing to disable all displays."

displayplacer "${new_args[@]}"
echo "Applied '${choice}': enabled ${enabled_names[*]}"
