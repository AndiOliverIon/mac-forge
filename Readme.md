### Important
This machine baseline uses Homebrew for .NET SDK management, including multiple side-by-side SDK casks. Keep this approach on future Macs for consistency.

# macOS Setup Notes

Personal notes for setting up a new Mac and restoring my usual environment.

---

## Station and device inventory lookup

When answering a question about a station, use these sources in order:

1. Read `configs/stations.json` first. Its `stations` collection is the
   canonical tracked inventory for compute stations; its `devices` collection
   holds docks, portable storage, and other attached hardware. It records names,
   roles, OS details, hardware specifications, connection types, aliases,
   availability, attachment relationships, and fact provenance.
   Use `configs/station-topology.md` for the corresponding tracked physical,
   display, and network diagrams.
2. Read `config-local/stations.json` when local network addressing or unique
   identifiers are required. It is ignored by Git and stores IP addresses,
   subnets, gateways, MAC addresses, VM UUIDs, and similar machine-local facts.
   Do not copy its values into tracked files or expose them unless the request
   specifically requires them.
3. Use operational configuration only to verify how a connection actually
   works:
   - `/etc/hosts` for friendly hostname resolution;
   - `~/.ssh/config` for SSH aliases and connection behavior, without exposing
     identity files or credentials;
   - Tailscale for overlay availability;
   - Parallels configuration for VM allocation and state.
4. Query the station read-only when current facts matter:
   - Hades: local `system_profiler`, `networksetup`, `ifconfig`, and `diskutil`;
   - MasterChief and vps1: `ssh <primaryAlias>` and native Linux inventory
     commands;
   - Cerber: `prlctl` while suspended or running, and SSH when available;
   - Charon: macOS CoreDevice via `xcrun devicectl` while paired over USB.
   - Hades-attached docks, storage, and displays: `diskutil`,
     `system_profiler`, and I/O topology, without collecting serial numbers or
     volume UUIDs.
5. Treat live reachability, DHCP addresses, mounted devices, and VM power state
   as observations rather than permanent capabilities. Record when facts were
   verified, and update the canonical inventory plus its ignored local overlay
   when a live result proves stored data is stale.

`configs/work-state.json` remains operational state for Forge workflows and
storage destinations; it is not a station inventory. Passwords, tokens,
private keys, certificates, and sensitive addressing must remain in ignored
local configuration or the existing secrets store.

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
- ghostty
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
brew install --cask arc bitwarden codex docker-desktop dotnet-sdk dotnet-sdk8 dotnet-sdk8-0-400 dotnet-sdk9 dotnet-sdk9-0-300 font-jetbrains-mono ghostty google-chrome google-drive iterm2 jetbrains-toolbox microsoft-teams raycast rectangle rustdesk visual-studio-code zed
```

### 0.3 Other Software (not from Homebrew)

Install these separately from vendor sources:

- FortiClient VPN (Fortinet): install only VPN component.
- CodeMeter/WIBU licensing: use the `vps1`-hosted CmCloud architecture in
  [CODEMETER.md](CODEMETER.md). Do not install CodeMeter Runtime on macOS for
  this setup.
- DevExpress .NET component licensing: download the assigned license file and
  install it at the user-level path described in
  [licenses/devexpress-suite-license.md](licenses/devexpress-suite-license.md).
  Do not install the Windows suite on macOS and never commit the license file.
- Parallels Desktop: needed when using Windows-side tools and shortcut cleanup workflow.
- Oh My Zsh: install from official GitHub project for shell profile baseline.

### 0.4 Ghostty shell initialization

iTerm2 uses the normal interactive zsh, with `~/.zshrc` symlinked to
`dotfiles/zshrc`. That file loads Powerlevel10k, the Forge macOS aliases,
VPS aliases, local environment variables, and the shared command-line tools.

Configure Ghostty to use the same shell initialization and the tracked Ghostty
settings:

```bash
./scripts/configure-ghostty.sh
```

The configurator creates these links:

- `~/.zshrc` -> `dotfiles/zshrc`
- `~/.p10k.zsh` -> `profiles/p10k.zsh`
- `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` ->
  `dotfiles/ghostty.ghostty`

Ghostty uses the normal interactive shell; the shared terminal config does not
hardcode a shell command. Existing files at those destinations are moved to a
timestamped backup before the links are created.

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

## 7. CodeMeter (Wibu) / ARDIS licensing

The authoritative license container is hosted by CodeMeter on `vps1`. The Mac
opens an SSH tunnel only when licensed software is needed:

```bash
v1-license-tunnel-up
v1-license-tunnel-status
v1-license-tunnel-down
```

See [CODEMETER.md](CODEMETER.md) for the complete architecture, activation and
recovery record, Windows/Parallels setup, verification, and troubleshooting.

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
   - [ ] Configure the `vps1` SSH alias and verify the on-demand license tunnel
     described in `CODEMETER.md`.
   - [ ] Install the DevExpress .NET license file as described in
     `licenses/devexpress-suite-license.md`.
7. Homebrew
   - [ ] Run `brew doctor`.
   - [ ] Run `brew outdated` and `brew upgrade` as needed.
