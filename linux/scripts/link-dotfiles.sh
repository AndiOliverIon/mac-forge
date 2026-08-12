#!/usr/bin/env bash

set -euo pipefail

backup_existing() {
  local target="$1"

  if [[ -L "$target" || ! -e "$target" ]]; then
    return
  fi

  mv "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
}

link_file() {
  local source_path="$1"
  local target_path="$2"

  backup_existing "$target_path"
  ln -sfn "$source_path" "$target_path"
  echo "Linked $target_path -> $source_path"
}

FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
LINUX_DOTFILES_DIR="${FORGE_ROOT}/linux/dotfiles"

[[ -d "$LINUX_DOTFILES_DIR" ]] || {
  echo "ERROR: Linux dotfiles directory not found: $LINUX_DOTFILES_DIR" >&2
  exit 1
}

link_file "$LINUX_DOTFILES_DIR/zshrc" "$HOME/.zshrc"
link_file "$LINUX_DOTFILES_DIR/p10k.zsh" "$HOME/.p10k.zsh"

MC_CONFIG_DIR="$HOME/.config/mc"
MC_SKINS_DIR="$HOME/.local/share/mc/skins"
mkdir -p "$MC_CONFIG_DIR" "$MC_SKINS_DIR"
link_file "$LINUX_DOTFILES_DIR/mc/skins/xoria256.ini" "$MC_SKINS_DIR/xoria256.ini"

if [[ -f "$MC_CONFIG_DIR/ini" ]]; then
  if grep -q '^skin=' "$MC_CONFIG_DIR/ini"; then
    sed -i 's/^skin=.*/skin=xoria256/' "$MC_CONFIG_DIR/ini"
  elif grep -q '^\[Midnight-Commander\]$' "$MC_CONFIG_DIR/ini"; then
    sed -i '/^\[Midnight-Commander\]$/a skin=xoria256' "$MC_CONFIG_DIR/ini"
  else
    cat >> "$MC_CONFIG_DIR/ini" <<'EOF'

[Midnight-Commander]
skin=xoria256
EOF
  fi
else
  cat > "$MC_CONFIG_DIR/ini" <<'EOF'
[Midnight-Commander]
skin=xoria256
EOF
fi
