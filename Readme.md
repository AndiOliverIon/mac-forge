# macOS Setup Notes

Personal notes for setting up a new Mac and restoring my usual environment.

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
Do **not** reapply the “extreme” key repeat tweaks. Keep default or only make mild adjustments if really necessary.

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

- Install **only** the **FortiClient VPN** component.
- Avoid installing the full Fortinet suite or any additional “extras” that come with their bigger bundle.

If the installer offers multiple options, deselect everything except the VPN client.

---

## 6. Python Installation (via pyenv)

Install Python using `pyenv` managed by Homebrew for better version control and isolation.

```bash
# Install pyenv
brew install pyenv
```

Then use `pyenv` to manage Python versions, for example:

```bash
# List available versions
pyenv install -l

# Install a specific version
pyenv install 3.12.0

# Set global/default Python version
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
# See which packages are outdated
brew outdated

# Upgrade all outdated packages
brew upgrade

# Check for potential issues and suggestions
brew doctor
```

Run `brew doctor` from time to time to check the health of the Homebrew installation and environment.

---

## 9. Quick Checklist for New Mac

1. **Dock**
   - [ ] Restore default behavior or set instant show/hide.

2. **Git**
   - [ ] Configure global `.gitignore` with `.DS_Store`.
   - [ ] Set correct `user.name` and `user.email` (personal vs work).

3. **Raycast / Parallels**
   - [ ] Run `win-shortcut-clean.sh` to remove unwanted Windows shortcuts.

4. **VPN**
   - [ ] Install **FortiClient VPN only**, not the full suite.

5. **Python**
   - [ ] Install `pyenv` via Homebrew.
   - [ ] Install and set a default Python version.

6. **Licensing**
   - [ ] If needed, verify CodeMeter is running; use restart command if not.

7. **Homebrew**
   - [ ] Run `brew doctor`.
   - [ ] Run `brew outdated` and `brew upgrade` as needed.