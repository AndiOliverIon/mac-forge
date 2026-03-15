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
