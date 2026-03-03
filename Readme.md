### Important
This machine baseline uses Homebrew for .NET SDK management, including multiple side-by-side SDK casks. Keep this approach on future Macs for consistency.

# macOS Setup Notes

Personal notes for setting up a new Mac and restoring my usual environment.

---

## 0. Baseline Software (Current Machine)

### 0.1 Homebrew Formulae (installed and required)

- bash
- displayplacer
- fzf
- gh
- git
- jq
- mas
- mono-libgdiplus
- ncdu
- nvm
- pyenv
- shfmt
- sqlcmd
- tree
- unzip
- wget
- yarn

Install all formulae at once:

```bash
brew install bash displayplacer fzf gh git jq mas mono-libgdiplus ncdu nvm pyenv shfmt sqlcmd tree unzip wget yarn
```

### 0.2 Homebrew Casks (installed and required)

- arc
- bitwarden
- codex
- docker-desktop
- dotnet-sdk
- dotnet-sdk8
- dotnet-sdk8-0-400
- dotnet-sdk9
- dotnet-sdk9-0-300
- font-jetbrains-mono
- google-chrome
- google-drive
- iterm2
- jetbrains-toolbox
- microsoft-teams
- raycast
- rectangle
- rustdesk
- visual-studio-code
- zed

Install all casks at once:

```bash
brew install --cask arc bitwarden codex docker-desktop dotnet-sdk dotnet-sdk8 dotnet-sdk8-0-400 dotnet-sdk9 dotnet-sdk9-0-300 font-jetbrains-mono google-chrome google-drive iterm2 jetbrains-toolbox microsoft-teams raycast rectangle rustdesk visual-studio-code zed
```

### 0.3 Other Software (not from Homebrew)

Install these separately from vendor sources:

- FortiClient VPN (Fortinet): install only VPN component.
- CodeMeter Runtime (Wibu): for local license handling.
- Parallels Desktop: needed when using Windows-side tools and shortcut cleanup workflow.
- Oh My Zsh: install from official GitHub project for shell profile baseline.

---

## 1. Dock Behavior

### 1.1 Restore Dock to default behavior

```bash
# Remove custom autohide delay and animation time
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock autohide-time-modifier

# Restart Dock to apply changes
killall Dock
```

### 1.2 Make Dock show/hide instantly

```bash
# Make Dock appear/disappear instantly
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0

# Restart Dock to apply changes
killall Dock
```

---

## 2. Git Configuration

### 2.1 Global ignore file

Configure a global `.gitignore` so some files are never tracked:

```bash
# Set global gitignore location
git config --global core.excludesfile ~/.gitignore_global

# Ignore macOS Finder metadata globally
echo ".DS_Store" >> ~/.gitignore_global
```

### 2.2 User identity

#### Personal (global)

Use these on a personal machine or when you want your personal identity:

```bash
git config --global user.name "Andi Ion Oliver"
git config --global user.email "andioliverion@gmail.com"
```

#### Work

Use these on a work machine (or switch as needed in specific repos):

```bash
git config --global user.name "Andi Ion Oliver"
git config --global user.email "andi@ardis.eu"
```

> Note: Consider using per-repository config (`git config user.name ...` without `--global`) if you regularly switch between personal and work projects on the same machine.

---

## 3. Keyboard Tuning

I previously experimented with very aggressive key repeat and delay settings and did **not** like the result.

**Note to self:**
Do **not** reapply the extreme key repeat tweaks. Keep default or only make mild adjustments if really necessary.

---

## 4. Raycast & Parallels Shortcuts

I use Raycast heavily.

One recurring problem: opening Windows (Parallels) applications by mistake when I meant to open the macOS version.

To clean this up:

- Use the `win-shortcut-clean.sh` script.
- Purpose of the script:
  - Remove unnecessary Windows application shortcuts.
  - Keep only the few Windows shortcuts that I actually need exposed on macOS.

Keep this script handy and re-run it after Parallels updates or when new shortcuts appear.

---

## 5. FortiClient VPN

When installing FortiClient:

- Install only the VPN component.
- Avoid installing the full Fortinet suite or additional extras.

---

## 6. Python Installation (via pyenv)

Install Python using `pyenv` managed by Homebrew for better version control and isolation.

```bash
brew install pyenv
```

Then use `pyenv` to manage Python versions, for example:

```bash
pyenv install -l
pyenv install 3.12.0
pyenv global 3.12.0
```

---

## 7. CodeMeter (Wibu) – Restart Service

To restart the CodeMeter server (e.g., when licenses or dongles are not picked up correctly):

```bash
sudo launchctl kickstart -k system/com.wibu.CodeMeter.Server
```

Run this if CodeMeter behaves strangely or licensed apps stop detecting the license.

---

## 8. Homebrew Maintenance

Basic maintenance commands:

```bash
brew outdated
brew upgrade
brew doctor
```

Run `brew doctor` from time to time to check the health of the Homebrew installation and environment.

---

## 9. Quick Checklist for New Mac

1. Dock
   - [ ] Restore default behavior or set instant show/hide.
2. Core software
   - [ ] Install baseline Homebrew formulae and casks from section 0.
   - [ ] Install non-Homebrew software from section 0.3.
3. Git
   - [ ] Configure global `.gitignore` with `.DS_Store`.
   - [ ] Set correct `user.name` and `user.email` (personal vs work).
4. Raycast / Parallels
   - [ ] Run `win-shortcut-clean.sh` to remove unwanted Windows shortcuts.
5. Python
   - [ ] Install `pyenv` via Homebrew.
   - [ ] Install and set a default Python version.
6. Licensing
   - [ ] If needed, verify CodeMeter is running; use restart command if not.
7. Homebrew
   - [ ] Run `brew doctor`.
   - [ ] Run `brew outdated` and `brew upgrade` as needed.
