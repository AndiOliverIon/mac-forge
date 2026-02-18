#!/usr/bin/env bash

set -euo pipefail

FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
ALIASES_FILE="$FORGE_ROOT/dotfiles/aliases"
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

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*alias[[:space:]]+([A-Za-z0-9._-]+)= ]] || continue
  name="${BASH_REMATCH[1]}"
  command_part="${line#*=}"

  # Trim one layer of wrapping quotes if present.
  if [[ "$command_part" =~ ^\".*\"$ || "$command_part" =~ ^\'.*\'$ ]]; then
    command_part="${command_part:1:${#command_part}-2}"
  fi

  entries+=("alias\t${name}\t${command_part}")
done < "$ALIASES_FILE"

if [[ -d "$SCRIPTS_DIR" ]]; then
  while IFS= read -r -d '' script_path; do
    script_name="$(basename "$script_path" .sh)"
    entries+=("script\t${script_name}\t${script_path}")
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
      --with-nth=1,2,3 \
      --preview='printf "Type: %s\nName: %s\n\nCommand:\n%s\n" {1} {2} {3}')"

[[ -z "$selection" ]] && exit 0

type_field="$(awk -F $'\t' '{print $1}' <<< "$selection")"
name_field="$(awk -F $'\t' '{print $2}' <<< "$selection")"
value_field="$(awk -F $'\t' '{print $3}' <<< "$selection")"

if [[ "$type_field" == "alias" ]]; then
  echo "Running alias: $name_field"
  exec zsh -ic "$name_field"
fi

if [[ "$type_field" == "script" ]]; then
  echo "Running script: $value_field"
  exec "$value_field"
fi

echo "Unknown selection type: $type_field"
exit 1
