#!/usr/bin/env bash

set -euo pipefail

# Interactive display switcher for Plasma Wayland (KScreen).
# Presents an fzf menu: All / Laptop only / Extended only.

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

require_cmd kscreen-doctor
require_cmd fzf

# Discover connected outputs, tagging the internal panel vs external displays.
INTERNAL=()
EXTERNAL=()

current_name=""
current_connected=0
current_panel=0

flush_output() {
  [[ -z "$current_name" ]] && return
  if ((current_connected)); then
    if ((current_panel)); then
      INTERNAL+=("$current_name")
    else
      EXTERNAL+=("$current_name")
    fi
  fi
}

while IFS= read -r line; do
  case "$line" in
    "Output: "*)
      flush_output
      current_name="$(awk '{print $3}' <<<"$line")"
      current_connected=0
      current_panel=0
      ;;
    *connected*) [[ "$line" != *disconnected* ]] && current_connected=1 ;;
    *Panel*) current_panel=1 ;;
  esac
done < <(kscreen-doctor -o | sed $'s/\x1b\\[[0-9;]*m//g')
flush_output

((${#INTERNAL[@]} + ${#EXTERNAL[@]} > 0)) || die "No connected outputs detected."

choice="$(printf '%s\n' 'All' 'Laptop only' 'Extended only' \
  | fzf --prompt='Display layout > ' --height=40% --reverse)"

[[ -n "$choice" ]] || { echo "Cancelled."; exit 0; }

args=()
enable_list=()

case "$choice" in
  'All')
    for o in "${INTERNAL[@]}" "${EXTERNAL[@]}"; do
      args+=("output.${o}.enable"); enable_list+=("$o")
    done
    ;;
  'Laptop only')
    ((${#INTERNAL[@]} > 0)) || die "No internal panel detected."
    for o in "${INTERNAL[@]}"; do args+=("output.${o}.enable"); enable_list+=("$o"); done
    for o in "${EXTERNAL[@]}"; do args+=("output.${o}.disable"); done
    ;;
  'Extended only')
    ((${#EXTERNAL[@]} > 0)) || die "No external display detected."
    for o in "${EXTERNAL[@]}"; do args+=("output.${o}.enable"); enable_list+=("$o"); done
    for o in "${INTERNAL[@]}"; do args+=("output.${o}.disable"); done
    ;;
  *)
    die "Unknown choice: $choice"
    ;;
esac

kscreen-doctor "${args[@]}"
echo "Applied '${choice}': enabled ${enable_list[*]}"
