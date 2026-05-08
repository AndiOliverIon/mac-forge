#!/usr/bin/env bash

set -euo pipefail

FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
ALIASES_FILE="$FORGE_ROOT/dotfiles/aliases"
DESCRIPTIONS_FILE="${ALIAS_DESCRIPTIONS_FILE:-$FORGE_ROOT/configs/alias-descriptions.tsv}"
SCRIPTS_DIR="$FORGE_ROOT/scripts"

if ! command -v fzf >/dev/null 2>&1; then
  echo "Error: fzf is required but not installed."
  exit 1
fi

if [[ ! -f "$ALIASES_FILE" ]]; then
  echo "Error: aliases file not found at $ALIASES_FILE"
  exit 1
fi

entries=()
description_keys=()
description_values=()

if [[ -f "$DESCRIPTIONS_FILE" ]]; then
  while IFS=$'\t' read -r desc_type desc_name desc_text _; do
    [[ -n "${desc_type:-}" && -n "${desc_name:-}" && -n "${desc_text:-}" ]] || continue
    [[ "$desc_type" == \#* ]] && continue
    description_keys+=("${desc_type}:${desc_name}")
    description_values+=("$desc_text")
  done < "$DESCRIPTIONS_FILE"
fi

description_for() {
  local key="$1:$2"
  local fallback="$3"
  local i

  for ((i = 0; i < ${#description_keys[@]}; i++)); do
    if [[ "${description_keys[$i]}" == "$key" ]]; then
      printf '%s' "${description_values[$i]}"
      return 0
    fi
  done

  printf '%s' "$fallback"
}

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*alias[[:space:]]+([A-Za-z0-9._-]+)= ]] || continue
  name="${BASH_REMATCH[1]}"
  command_part="${line#*=}"
  description="$(description_for alias "$name" "No description yet.")"

  # Trim one layer of wrapping quotes if present.
  if [[ "$command_part" =~ ^\".*\"$ || "$command_part" =~ ^\'.*\'$ ]]; then
    command_part="${command_part:1:${#command_part}-2}"
  fi

  entries+=("alias\t${name}\t${description}\t${command_part}")
done < "$ALIASES_FILE"

if [[ -d "$SCRIPTS_DIR" ]]; then
  while IFS= read -r -d '' script_path; do
    script_name="$(basename "$script_path" .sh)"
    description="$(description_for script "$script_name" "Executable forge script.")"
    entries+=("script\t${script_name}\t${description}\t${script_path}")
  done < <(find "$SCRIPTS_DIR" -maxdepth 1 -type f -name "*.sh" -perm -u+x -print0 | sort -z)
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "No commands found."
  exit 0
fi

selection="$({ printf '%b\n' "${entries[@]}"; } \
  | awk -F $'\t' '!seen[$1 FS $2]++' \
  | sort -t $'\t' -k1,1 -k2,2 \
  | fzf \
      --height=85% \
      --layout=reverse \
      --border \
      --prompt='forge-help> ' \
      --header='Type to filter, Enter to execute, Esc to cancel' \
      --delimiter=$'\t' \
      --with-nth=1,2 \
      --nth=2,3,4 \
      --preview='printf "Type: %s\nName: %s\nDescription: %s\n\nCommand:\n%s\n" {1} {2} {3} {4}')"

[[ -z "$selection" ]] && exit 0

type_field="$(awk -F $'\t' '{print $1}' <<< "$selection")"
name_field="$(awk -F $'\t' '{print $2}' <<< "$selection")"
command_field="$(awk -F $'\t' '{print $4}' <<< "$selection")"

if [[ "$type_field" == "alias" ]]; then
  echo "Running alias: $name_field"
  exec zsh -ic "$name_field"
fi

if [[ "$type_field" == "script" ]]; then
  echo "Running script: $command_field"
  exec "$command_field"
fi

echo "Unknown selection type: $type_field"
exit 1
