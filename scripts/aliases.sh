#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
else
  # shellcheck disable=SC1091
  source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Helpers
#######################################
die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

#######################################
# Preconditions
#######################################
require_cmd fzf
require_cmd rg

CLIP_CMD="${CLIP_CMD:-pbcopy}"
if [[ -n "${CLIP_CMD:-}" ]] && ! command -v "$CLIP_CMD" >/dev/null 2>&1; then
  CLIP_CMD=""
fi

#######################################
# Determine dotfiles path
#######################################
FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
DOTFILES_DIR="${DOTFILES_DIR:-$FORGE_ROOT/dotfiles}"
[[ -d "$DOTFILES_DIR" ]] || die "dotfiles folder not found: $DOTFILES_DIR"

#######################################
# Alias files (tight list; edit if needed)
#######################################
KNOWN_ALIAS_FILES=(
  "$DOTFILES_DIR/.aliases"
  "$DOTFILES_DIR/aliases"
  "$DOTFILES_DIR/aliases.zsh"
  "$DOTFILES_DIR/zsh/aliases.zsh"
  "$DOTFILES_DIR/zsh/aliases"
  "$DOTFILES_DIR/.zshrc"
  "$DOTFILES_DIR/.bashrc"
  "$DOTFILES_DIR/.bash_aliases"
  "$DOTFILES_DIR/fish/aliases.fish"
)

files=()
for f in "${KNOWN_ALIAS_FILES[@]}"; do
  [[ -f "$f" ]] && files+=("$f")
done

# Fallback: scan dotfiles for files containing alias-ish patterns
if ((${#files[@]} == 0)); then
  mapfile -t files < <(
    rg -l --hidden --follow --no-messages \
      -g'!.git/**' \
      -e '^[[:space:]]*alias([[:space:]]+-g)?[[:space:]]+' \
      -e '^[[:space:]]*abbr[[:space:]]+-a[[:space:]]+' \
      "$DOTFILES_DIR" \
    || true
  )
fi

((${#files[@]} > 0)) || die "No alias files found in: $DOTFILES_DIR"

#######################################
# Build rows:
#   col1 = alias name (what you filter by)
#   col2 = relative path (from FORGE_ROOT) + :line (display)
#   col3 = full path (preview)
#   col4 = line number (preview)
#######################################
declare -A seen=()
rows=()

while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue

  file="${hit%%:*}"
  rest="${hit#*:}"
  line_no="${rest%%:*}"
  content="${rest#*:}"

  [[ "$content" =~ ^[[:space:]]*# ]] && continue

  name=""
  if [[ "$content" =~ ^[[:space:]]*alias([[:space:]]+-g)?[[:space:]]+([A-Za-z0-9_:\-]+)[[:space:]]*= ]]; then
    name="${BASH_REMATCH[2]}"
  elif [[ "$content" =~ ^[[:space:]]*abbr[[:space:]]+-a[[:space:]]+([A-Za-z0-9_:\-]+) ]]; then
    name="${BASH_REMATCH[1]}"
  fi
  [[ -n "$name" ]] || continue

  # Relative path from FORGE_ROOT so you see dotfiles/...
  rel="$file"
  if [[ "$file" == "$FORGE_ROOT/"* ]]; then
    rel="${file#"$FORGE_ROOT"/}"
  elif [[ "$file" == "$DOTFILES_DIR/"* ]]; then
    rel="dotfiles/${file#"$DOTFILES_DIR"/}"
  fi

  if [[ -z "${seen[$name]+x}" ]]; then
    seen["$name"]=1
    rows+=("${name}"$'\t'"${rel}:${line_no}"$'\t'"${file}"$'\t'"${line_no}")
  fi
done < <(
  rg -n --with-filename --no-heading --hidden --follow --no-messages \
    -g'!.git/**' \
    -e '^[[:space:]]*alias([[:space:]]+-g)?[[:space:]]+[A-Za-z0-9_:\-]+[[:space:]]*=' \
    -e '^[[:space:]]*abbr[[:space:]]+-a[[:space:]]+[A-Za-z0-9_:\-]+' \
    "${files[@]}" \
  || true
)

((${#rows[@]} > 0)) || die "No alias names found."

#######################################
# fzf
# Preview shows ONLY the selected alias line (no big context window)
#######################################
selected="$(
  printf '%s\n' "${rows[@]}" | fzf \
    --prompt="aliases> " \
    --height=80% \
    --layout=reverse \
    --border \
    --delimiter=$'\t' \
    --with-nth=1,2 \
    --preview-window='right:60%:wrap' \
    --preview='bash -lc '"'"'
      name="{1}"
      rel_and_line="{2}"
      file="{3}"
      ln="{4}"

      echo "$rel_and_line"
      echo

      # Print exactly the definition line from the file.
      # Use sed line addressing so it’s fast and exact.
      # (ln is already the line number from rg when we built rows.)
      sed -n "${ln}p" "$file"
    '"'"''
)" || exit 0

alias_name="$(printf "%s" "$selected" | cut -f1)"

# Output just the shortcut
echo "$alias_name"

# Optional: copy shortcut
if [[ -n "${CLIP_CMD:-}" ]]; then
  printf '%s' "$alias_name" | "$CLIP_CMD"
fi
