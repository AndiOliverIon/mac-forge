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

ensure_bash_aliases() {
  local target_path="$HOME/.bashrc"
  local source_line='[[ -r "$HOME/mac-forge/linux/aliases.zsh" ]] && source "$HOME/mac-forge/linux/aliases.zsh"'

  [[ -f "$target_path" ]] || return
  grep -Fqx -- "$source_line" "$target_path" && return

  {
    printf '\n# Load Forge aliases in Omarchy Bash.\n'
    printf '%s\n' "$source_line"
  } >> "$target_path"
  echo "Linked Forge aliases into $target_path"
}

FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
LINUX_DOTFILES_DIR="${FORGE_ROOT}/linux/dotfiles"

[[ -d "$LINUX_DOTFILES_DIR" ]] || {
  echo "ERROR: Linux dotfiles directory not found: $LINUX_DOTFILES_DIR" >&2
  exit 1
}

link_file "$LINUX_DOTFILES_DIR/zshrc" "$HOME/.zshrc"
link_file "$LINUX_DOTFILES_DIR/p10k.zsh" "$HOME/.p10k.zsh"
ensure_bash_aliases
