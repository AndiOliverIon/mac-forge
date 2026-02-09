# Terminal Personalization

This directory contains prompt configuration for **Windows (Oh My Posh)** and **macOS (Oh My Zsh + Powerlevel10k)**, synced via this repository.

## Goal

Show the **station name (hostname) only when on SSH**:

- **SSH session** → hostname appears on the top line.
- **Local session** → hostname hidden (clean prompt).

---

## Windows (PowerShell + Oh My Posh)

### Files
- `omp/minimal.omp.json` (Oh My Posh theme)

### Install / enable
1. Ensure Oh My Posh is installed:
   - `winget install JanDeDobbeleer.OhMyPosh` (or your preferred method)

2. Point your PowerShell profile to the repo theme.

Open your profile:
```powershell
notepad $PROFILE
```

Add (edit the path to your repo):
```powershell
oh-my-posh init pwsh --config "$HOME\<path-to-your-repo>\omp\minimal.omp.json" | Invoke-Expression
```

Reload:
```powershell
. $PROFILE
```

### Verify SSH-only hostname behavior
- Local terminal: no hostname shown
- Inside SSH session: hostname shown

---

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

- On Windows: when you `ssh` to another machine, the prompt you see is the **remote machine’s prompt**. So SSH-only hostname must be configured on **each station** you SSH *into* (macOS boxes included).
- To tweak colors/layout:
  - Windows: edit `omp/minimal.omp.json`
  - macOS: edit `zsh/p10k.zsh` (custom segment is `prompt_station`)
