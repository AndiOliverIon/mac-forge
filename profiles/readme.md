# Terminal Personalization

This directory contains prompt configuration for **macOS (Oh My Zsh + Powerlevel10k)**, synced via this repository.

## Goal

Show the **station name (hostname) only when on SSH**:

- **SSH session** → hostname appears on the top line.
- **Local session** → hostname hidden (clean prompt).

## macOS (zsh + Oh My Zsh + Powerlevel10k)

### Files
- `zsh/p10k.zsh` (Powerlevel10k configuration with SSH-only hostname segment)

### Install / enable
1. Make sure `~/.zshrc` loads Powerlevel10k and sources `~/.p10k.zsh` (already the case).

2. Symlink the repo config into place:

```zsh
ln -sf "$HOME/<path-to-your-repo>/zsh/p10k.zsh" "$HOME/.p10k.zsh"
```

3. Reload:
```zsh
source ~/.zshrc
```
(or restart the terminal)

### Verify SSH-only hostname behavior
- Local terminal: no hostname shown
- Inside SSH session: hostname shown (short hostname)

---

## Notes

- To tweak colors/layout:
  - macOS: edit `zsh/p10k.zsh` (custom segment is `prompt_station`)
