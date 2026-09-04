# Omarchy Linux Workstation

A list of tools and configurations for the Omarchy workstation.

## Bootstrap

Run the workstation bootstrap from the repository root:

```bash
./linux/scripts/bootstrap.sh
```

The script targets Omarchy on Arch Linux. It installs missing Arch packages
through `omarchy pkg add`, configures the mise-managed Node.js toolchain, and
installs the native versioned .NET SDK packages used by the Ardis projects. It
does not run a distribution upgrade or remove packages.

The bootstrap preserves Omarchy's Hyprland, Bash, and user configuration. The
Forge Zsh profile remains available through `exec zsh`; it is not made the
default shell automatically.

The bootstrap installs JetBrains Toolbox from JetBrains' current Linux release
and verifies its published SHA-256 checksum. After bootstrap, open Toolbox and
install Rider from there. Do not install Rider through Snap; the native Toolbox
installation integrates with the Omarchy application launcher.

Before running the bootstrap, a Telerik license can be staged as
`.telerik/telerik-license.txt` in the launch directory or under
`/data/forge-temp`. The bootstrap installs it as
`~/.telerik/telerik-license.txt` with owner-only permissions. Set
`TELERIK_LICENSE_SOURCE_DIR` to use another source directory. The source copy
is deliberately retained for verification and should be removed afterward.

If a Data SSD is formatted and mounted read/write at `/data` through
`/etc/fstab`, the bootstrap prepares its SQL and Docker layout and installs the
SMB share. The bootstrap intentionally does not partition disks or edit
`fstab`. Without `/data`, Docker uses the normal system storage path and the
Data SSD steps are skipped. Linux SQL helpers use `/data/sql/docker` when that
mount is available and automatically fall back to
`~/.local/share/forge/sql/docker` on the system disk.

The Forge Zsh prompt sources `profiles/p10k.zsh`, which is the macOS master
Powerlevel10k personalization. Do not run `p10k configure` independently on
Linux; update the master profile instead. Omarchy Bash remains the default
interactive shell.

Ghostty split shortcuts:

- `Alt+D`: split horizontally, opening the new panel on the right
- `Alt+Shift+D`: split vertically, opening the new panel below
- `Alt+W`: close the focused panel
- `Ctrl+Alt+Arrow`: move between splits

Focused panels close immediately without a confirmation prompt.

The Ghostty config can be shared with macOS from the neutral repo file
`dotfiles/ghostty.ghostty`. On a fresh setup, bootstrap links it to Omarchy's
native `~/.config/ghostty/config` path. An existing Omarchy Ghostty config is
preserved; merge changes deliberately before replacing it.

## MasterChief agent workspaces

Raynor and Zeratul each use a separate tmux server and persistent session. From
Hades or MasterChief, enter the corresponding universe with:

```bash
raynor
zeratul
```

Each command creates its session when absent and otherwise reattaches to it.
Raynor starts at `/home/oliver/raynor`; Zeratul starts at
`/home/oliver/zeratul`. Detach with `Ctrl+B`, then `d`. The shell and any agent
running inside it remain active after detaching or losing the SSH connection.

Plain `raynor` and `zeratul` remain the smart defaults. Optional lifecycle
actions provide more deliberate control when needed:

```bash
raynor start        # Create it in the background when absent.
raynor attach       # Attach only if it already exists.
raynor shell        # Open an independent terminal in Raynor's universe.
raynor status       # Show state, command, directory, and start time.
raynor logs         # Show the last 100 lines without attaching.
raynor logs 250     # Show a chosen number of recent lines.
raynor stop         # Confirm before terminating the session.
```

The same actions work with `zeratul`. `attach` reports an error instead of
creating a missing session, while the plain command continues to create one
when necessary. `shell` uses the current terminal or iTerm2 pane and ends when
you type `exit`; it never creates, attaches to, or stops the persistent tmux
session.

The base tmux workflow remains available inside the persistent session. Press
`Ctrl+B`, then `c` to create another tmux window, and use `Ctrl+B`, then `0`,
`1`, or `w` to select a window. In a separate iTerm2 pane, use `raynor shell`
or `zeratul shell` when both terminals need to remain visible simultaneously.

Inside an agent session, the existing work aliases automatically resolve under
that identity's universe. For example, `perf` enters
`/home/oliver/raynor/ardis-perform` for Raynor and
`/home/oliver/zeratul/ardis-perform` for Zeratul. In a normal MasterChief shell,
the same alias remains `/home/oliver/work/ardis-perform`. This applies to all
Linux aliases based on the work root, including `work`, `perf230`, `timetrack`,
`gpt`, and `localconnector`.

Agent shells reject accidental directory changes outside their universe. The
session-specific `codex` function starts Codex in the current directory with
`workspace-write` and approval-on-request, and rejects command-line options
that could replace or broaden that boundary. MasterChief's bootstrap installs
the Linux `bubblewrap` prerequisite used for reliable Codex sandboxing.

MasterChief also hosts two isolated worker identities:

- Raynor uses `/home/oliver/raynor`.
- Zeratul uses `/home/oliver/zeratul`.

At most two agents may run on MasterChief: one Raynor and one Zeratul. These
universe roots are directories owned by the `oliver` Linux account, not
separate user homes or accounts. Raynor must work only inside its own root and
must never inspect or modify Zeratul's root; Zeratul has the inverse boundary.
Launch each agent with only its own universe configured as writable, and never
start a third agent on this station.

Committed feature branches move directly between Hades and MasterChief over
SSH without touching `origin`. Hades work repositories live below `~/work`.
Their MasterChief counterpart is selected explicitly:

```text
mc2h  / h2mc   MasterChief personal work
r2h   / h2r    Raynor
z2h   / h2z    Zeratul
```

Run commands ending in `2h` from the Hades repository. Run commands beginning
with `h2` from the intended destination repository on MasterChief. For example:

```bash
r2h   # Raynor to the current Hades repository.
h2r   # Hades to the current Raynor repository.
```

Each command opens an fzf picker containing that source's transferable feature
branches, with the current local branch first when it is also available. Pass a
branch name directly to skip the picker, for example
`r2h aoi/per-1234-feature-dev`. The destination commands validate that `h2r`
runs below `/home/oliver/raynor` and `h2z` runs below
`/home/oliver/zeratul`; a mismatch is refused. Standard home-relative
repositories such as `~/mac-forge` remain supported by `mc2h` and `h2mc`.

The first import creates the local branch without assigning the peer as its
upstream. Later transfers require a clean worktree and advance only by
fast-forward. Diverged histories and protected base branches are refused. The
workflow transfers committed Git history only; uncommitted files never move.

## Private Forge configuration

Linux reads its private configuration from:

```text
~/.config/forge/forge-secrets.sh
```

The existing macOS-compatible `FORGE_SQL_SA_PASSWORD` variable is reused by
Linux commands such as `dbr`, `dbsn`, and `am`. Non-sensitive Linux paths stay
in `linux/config/runtime.json`.

The bootstrap creates `~/.config/forge` with owner-only permissions, but it
does not create or copy secret values. `XDG_CONFIG_HOME` and `FORGE_HOME_ROOT`
can override this default. Existing `/data/forge/forge-secrets.sh` files remain
supported as a legacy fallback.

## Local LAN Codex profile

Copy the secure `llm cli deploy` bundle to the Linux station, open a terminal
in that folder, and run `codex-local-register`. The command asks for sudo only
to trust the bundled certificate, then creates the `local-lan` Codex profile.
Use `codex --profile local-lan` afterwards. The bundle contains an API key and
must not be committed or left on shared storage.

## Remote SQL backups

Use `rdbsn` to select a remote SQL Server and create a compressed, copy-only
backup in that server's configured backup directory. The command uses the
shared `scripts/db-remote-backup.sh` workflow and requires remote targets in:

```text
~/mac-forge/config-local/local-store.json
```

The bootstrap attempts to install the `mssql-tools18` AUR package, which
provides Microsoft's standalone `sqlcmd` utility. If the AUR package is
unavailable, install it later with `omarchy pkg aur add mssql-tools18`. Remote
SQL credentials remain machine-local and are not created or copied by
bootstrap.

Use `rdown` to select a `.bak` or `.bkp` file from the Portainer SMB share and
download it to one of the destinations configured in
`configs/work-state.json`. On Linux, `rdown` uses the mounted share for its
file picker, then downloads through the authenticated Samba client to avoid
the kernel CIFS guest-session limitation. If the share is not mounted yet,
`rdown` mounts it automatically (prompting for sudo once); you can also mount
it beforehand with `mnt`. Interrupted files
remain with a `.part` suffix and resume on the next attempt. During transfer,
the command shows percentage, downloaded size, total size, and current speed.

Use `dbr` to restore a selected `.bak` into this station's `forge-sql` Docker
container. Use `dbo`, select `Local Docker (Default)`, then select the restored
database to run the configured Ardis table cleanup and database shrink. The
optimization can delete data and requires confirmation before it starts.

Use `dbrf` for the file-based variant of `dbr`: instead of a `.bak`, it attaches
a database from a selected `.mdf` (plus its matching `.ldf` when present),
proposing a database name extracted from the file that you can accept or
override.

Use `dblist` to list the local SQL databases with their total, data, and log
allocation, state, and recovery model.

Use `mnt` to select and mount a saved network share by friendly title. Mounts
are configured under `mounts` in `linux/config/runtime.json`. The picker shows
the title, remote source, and local mountpoint, and supports type-to-filter.

SMB passwords are not stored in the JSON configuration. Create the credential
file named by each mount with owner-only permissions, using this format:

```text
username=your-user
password=your-password
```

For the Ardis SQL backup share, use `~/.smbcredentials-ardis`; the Hades work
share uses `~/.smbcredentials`. Then secure the file, reload the shell, and
mount the selected share:

```bash
chmod 600 ~/.smbcredentials-ardis
reloadterm
mnt
```

## VPN

The Linux shell provides the same VPN commands as macOS:

```bash
vpn
vpns
dvpn
```

They use OpenConnect's Fortinet protocol support, connection metadata from
`configs/work-state.json`, and the matching password variable from
`~/.config/forge/forge-secrets.sh`. For example, a connection with ID `ARDIS`
requires `FORGE_VPN_ARDIS_PASSWORD`.

## Web launcher

Use `web` to select an entry from the shared `configs/web.json` list and open
it in the browser configured by `configs/work-state.json`. Use `web change` to
select a different browser. Linux falls back to the system default browser when
the configured application is unavailable.

## Docker

Install native Docker Engine with its daemon and containerd storage. When
`/data` is mounted read/write, the bootstrap uses `/data/docker`; otherwise it
uses Docker's normal `/var/lib/docker` path:

```bash
sudo ./linux/scripts/install-docker.sh
```

Log out and back in after installation so membership in the `docker` group
takes effect.

Docker Engine is disabled at boot on this station. Start it on demand and wait
for the daemon to become ready with:

```bash
docker-on
# Short form:
don
```

## Data share

Share `/data` with authenticated SMB access on the local network:

```bash
sudo ./linux/scripts/install-data-share.sh
sudo smbpasswd -a "$USER"
```

Connect from macOS using:

```text
smb://masterchief/Data
```

If local hostname resolution needs the mDNS suffix, use
`smb://masterchief.local/Data`.

The SMB password is deliberately not automated. Set it after bootstrap:

```bash
sudo smbpasswd -a "$USER"
```

## Private npm feeds

The Angular client uses private Ardis Azure Artifacts packages. Bootstrap does
not store or generate npm credentials. Copy a valid user-level npm
configuration to `~/.npmrc`, or authenticate with an Azure DevOps PAT that has
Packaging Read permission, before running `npm ci`.

Bootstrap installs Angular CLI `20.3.16`, matching
`ardis-perform/ardis.perform.client`, and installs Arch's Yarn `1.22.22`
package. The project README mentions
`vsts-npm-auth`, but that package exposes a Windows executable and is not used
as the Linux authentication method.

After adding Azure Artifacts credentials:

```bash
cd ~/work/ardis-perform/ardis.perform.client
npm ci
ng serve
```

Commercial UI licensing is also intentionally manual:

- Set `DEVEXTREME_KEY` before `npm ci` if a DevExtreme license key is required.
- The bootstrap installs a staged `.telerik/telerik-license.txt`; run
  `npx kendo-ui-license activate` from the Angular client to verify the
  entitlement after `npm ci`.

## Window Management

The active Linux desktop is Omarchy with Hyprland on Wayland. Personal
Hyprland settings belong in `~/.config/hypr/`; Omarchy's packaged defaults under
`/usr/share/omarchy/` are read-only.

The bootstrap does not replace Hyprland or write display settings. Keep
monitor, keybinding, animation, and appearance changes in the user Hyprland
configuration.

Use `sim` to cycle focus through the open, non-minimized applications captured
when the command starts:

```bash
sim
sim --cycle 30
```

The second form saves the interval in seconds. `sim` stays in the foreground
and unloads its temporary KWin script when stopped with `Ctrl+C`. It is a
legacy Plasma/KWin utility and is not part of the Omarchy bootstrap.

The command requires a Plasma/KWin session, one of `qdbus6`, `qdbus-qt6`, or
`qdbus`, plus the matching pointer-injection dependencies. It is retained for
older Plasma installations and is not supported by the current Hyprland
session.

## Utilities

Run the non-destructive workstation drift report after setup or desktop/package
changes. The same aliases work from Hades and MasterChief:

```bash
verify-workstation
# Short form:
vw
```

It checks the Omarchy/Hyprland session, optional `/data`, core packages and
commands, services, portals, Docker configuration, SSH agent state, displays,
failed units, and the static configuration of both MasterChief agent universes. When Raynor or Zeratul is
running, it also verifies that session's identity variables and pane boundary;
a stopped agent session is reported as a valid state. The report does not start
services or sessions, connect the VPN, access secrets, or change machine state.
From Hades, the command connects to MasterChief over SSH and marks graphical
session and connected-display checks as skipped because those facts cannot be
measured accurately through the remote shell.

### Cleanup

Use `linux-clean --dry-run` to preview the approved reconstructible caches, then
run `linux-clean` to clean them. `linux-clean --full` additionally includes
desktop thumbnail and shader caches. The cleanup preserves credentials,
sessions, configuration, project state, package stores needed for builds,
Docker containers/images/volumes, SQL data, Rider history, and system logs.
Chrome and Brave cleanup is limited to per-profile disk and compiled-code
caches and is skipped for each browser while that browser is running.
Every run ends with the gain from each cleaner and a combined total; dry runs
show the estimated potential gain and applied runs show the measured reduction.

- `load-workspace.sh` is retained only as a legacy i3 layout reference and
  refuses to run outside i3 because it closes windows on its target workspace.
- `disp` switches the current Hyprland session between all connected displays,
  the laptop panel, and external displays. Persist lasting monitor changes in
  `~/.config/hypr/monitors.lua`.
- `setup-display.sh` is retained only for its old X11 connector layout and
  refuses to run on Wayland. Configure current displays through Hyprland and
  the Omarchy monitor configuration.

## SSH & Shell Configuration

The optional Linux Zsh configuration sources the shared
`dotfiles/aliases-vps1` file. This provides the same on-demand CodeMeter tunnel
commands used on macOS:

```bash
v1-license-tunnel-up
v1-license-tunnel-status
v1-license-tunnel-down
```

The tunnel forwards local `127.0.0.1:22350` to the private CodeMeter service on
`vps1`. It is only active after running the `up` command.

### Hades development tunnel

When the Angular and Perform API development servers run on Hades, expose them
to this Linux station over the LAN through the Hades SSH tunnel:

```bash
hades-tunnel-up      # htu
hades-tunnel-down    # htd
hades-tunnel-status
```

While the tunnel is up, the station reaches the Hades services at
`http://localhost:4200` (Angular) and `http://localhost:8080` (Perform API).
Hades must have Remote Login enabled and key-based SSH access must work. The
tunnel connects through the `hades` SSH host alias by default; set
`HADES_SSH_HOST` (e.g. `hades`) or `HADES_TUNNEL_PORTS` to
override the defaults.

### SSH agent

The tracked Linux Zsh configuration establishes a usable SSH agent for normal
shells and persistent Raynor and Zeratul sessions. It preserves an existing
working `SSH_AUTH_SOCK`; otherwise it looks for the desktop GCR, OpenSSH, or
GnuPG agent socket under `XDG_RUNTIME_DIR`. If none is usable, it starts a
fallback agent on a stable runtime socket.

When the selected agent has no identities, the shell silently loads the
existing `~/.ssh/ardis_ed25519` and
`~/.ssh/andioliverion_ed25519` keys. Missing key files are skipped. A
running `ssh-agent` process alone is not considered sufficient because the
current shell must also have its usable socket in `SSH_AUTH_SOCK`.

After pulling a Zsh configuration update into MasterChief, start a fresh shell
inside an existing tmux session:

```bash
exec zsh
```

Check the active socket and loaded identities with:

```bash
print -r -- "$SSH_AUTH_SOCK"
ssh-add -l
```
