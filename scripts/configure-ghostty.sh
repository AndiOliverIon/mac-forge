#!/opt/homebrew/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"

[[ "$(uname -s)" == "Darwin" ]] || {
	echo "ERROR: This configurator is for macOS." >&2
	exit 1
}

link_file() {
	local source_path="$1"
	local target_path="$2"
	local backup_path

	[[ -f "$source_path" ]] || {
		echo "ERROR: Source file not found: $source_path" >&2
		exit 1
	}

	if [[ -L "$target_path" && "$(readlink "$target_path")" == "$source_path" ]]; then
		echo "Already linked: $target_path"
		return
	fi

	if [[ -e "$target_path" || -L "$target_path" ]]; then
		backup_path="${target_path}.backup.$(date +%Y%m%d-%H%M%S)"
		mv "$target_path" "$backup_path"
		echo "Backed up: $target_path -> $backup_path"
	fi

	ln -s "$source_path" "$target_path"
	echo "Linked: $target_path -> $source_path"
}

mkdir -p "$GHOSTTY_CONFIG_DIR"

# Ghostty starts the normal interactive zsh. These are the same Forge shell
# entry points used by iTerm2, so aliases, environment, and prompt stay shared.
link_file "$FORGE_ROOT/dotfiles/zshrc" "$HOME/.zshrc"
link_file "$FORGE_ROOT/profiles/p10k.zsh" "$HOME/.p10k.zsh"
link_file "$FORGE_ROOT/dotfiles/ghostty.ghostty" "$GHOSTTY_CONFIG_DIR/config.ghostty"

echo "Ghostty now uses the Forge macOS shell configuration. Open a new terminal."
