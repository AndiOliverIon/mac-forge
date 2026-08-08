# Linux Fresh Install Checklist

A list of essential tools and configurations for a fresh Linux installation.

## Bootstrap

Run the workstation bootstrap from the repository root:

```bash
./linux/scripts/bootstrap.sh
```

The script installs the core development tools, IDEs, terminal, shell, and
Powerlevel10k setup used on the Plasma workstation. It also installs `fzf` and
configures native Docker Engine with storage under `/data/docker`. It does not
run `apt autoremove`; review that package list manually because desktop
metapackage changes can make important system packages appear unused.

The bootstrap installs JetBrains Toolbox from JetBrains' current Linux release
and verifies its published SHA-256 checksum. After bootstrap, open Toolbox and
install Rider from there. Do not install Rider through Snap; the native Toolbox
installation integrates with KDE's launcher and existing-window activation.

Before running the bootstrap, a Telerik license can be staged as
`.telerik/telerik-license.txt` in the launch directory or under
`/data/forge-temp`. The bootstrap installs it as
`~/.telerik/telerik-license.txt` with owner-only permissions. Set
`TELERIK_LICENSE_SOURCE_DIR` to use another source directory. The source copy
is deliberately retained for verification and should be removed afterward.

Before running it, the Data SSD must already be formatted and mounted
read/write at `/data` through `/etc/fstab`. The bootstrap intentionally does
not partition disks or edit `fstab`.

The Linux prompt sources `profiles/p10k.zsh`, which is the macOS master
Powerlevel10k personalization. Do not run `p10k configure` independently on
Linux; update the master profile instead.

Ghostty split shortcuts:

- `Alt+D`: split horizontally, opening the new panel on the right
- `Alt+Shift+D`: split vertically, opening the new panel below
- `Alt+W`: close the focused panel
- `Ctrl+Alt+Arrow`: move between splits

Focused panels close immediately without a confirmation prompt.

## Private Forge configuration

Linux reads its private configuration from:

```text
/data/forge/forge-secrets.sh
```

The existing macOS-compatible `FORGE_SQL_SA_PASSWORD` variable is reused by
Linux commands such as `dbr`, `dbsn`, and `am`. Non-sensitive Linux paths stay
in `linux/config/runtime.json`.

The bootstrap creates `/data/forge` with owner-only permissions, but it does
not create or copy secret values.

## Remote SQL backups

Use `rdbsn` to select a remote SQL Server and create a compressed, copy-only
backup in that server's configured backup directory. The command uses the
shared `scripts/db-remote-backup.sh` workflow and requires remote targets in:

```text
~/mac-forge/config-local/local-store.json
```

The bootstrap installs Microsoft's standalone `sqlcmd` utility required by
this workflow. Remote SQL credentials remain machine-local and are not created
or copied by bootstrap.

Use `rdown` to select a `.bak` or `.bkp` file from the Portainer SMB share and
download it to one of the destinations configured in
`configs/work-state.json`. On Linux, `rdown` uses the mounted share for its
file picker, then downloads through the authenticated Samba client to avoid
the kernel CIFS guest-session limitation. Run `mnt` first. Interrupted files
remain with a `.part` suffix and resume on the next attempt. During transfer,
the command shows percentage, downloaded size, total size, and current speed.

Use `dbr` to restore a selected `.bak` into this station's `forge-sql` Docker
container. Use `dbo`, select `Local Docker (Default)`, then select the restored
database to run the configured Ardis table cleanup and database shrink. The
optimization can delete data and requires confirmation before it starts.

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
`/data/forge/forge-secrets.sh`. For example, a connection with ID `ARDIS`
requires `FORGE_VPN_ARDIS_PASSWORD`.

## Web launcher

Use `web` to select an entry from the shared `configs/web.json` list and open
it in the browser configured by `configs/work-state.json`. Use `web change` to
select a different browser. Linux falls back to the system default browser when
the configured application is unavailable.

## Docker

Install native Docker Engine with its daemon and containerd storage under
`/data/docker`:

```bash
sudo ./linux/scripts/install-docker.sh
```

Log out and back in after installation so membership in the `docker` group
takes effect.

Docker Engine is disabled at boot on the secondary Linux station. Start it on
demand and wait for the daemon to become ready with:

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
`ardis-perform/ardis.perform.client`, and activates Yarn `1.22.22` through
Corepack. The project README mentions
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

The active Linux desktop is KDE Plasma with KWin.

The bootstrap assigns virtual-desktop navigation to `Meta+Ctrl+Arrow`, leaving
`Ctrl+Alt+Arrow` available for Ghostty split navigation. It does not write
GNOME settings.

Use `sim` to cycle focus through the open, non-minimized applications captured
when the command starts:

```bash
sim
sim --cycle 30
```

The second form saves the interval in seconds. `sim` stays in the foreground
and unloads its temporary KWin script when stopped with `Ctrl+C`. It supports
Plasma on Wayland and X11. After activating each app, it moves the pointer to
the focused window, performs a brief 24-pixel horizontal and vertical movement
without clicking, and restores the original pointer position. Window state and
application content are not changed.

The command requires one of `qdbus6`, `qdbus-qt6`, or `qdbus`, plus
`libglib2.0-bin`, `python3-gi`, and `ydotool` with its user service running and
`/dev/uinput` access. The bootstrap installs and enables this support. Sign out
and back in after bootstrap if it adds the user to the `input` group.

## Utilities

Run the non-destructive workstation drift report after setup or desktop/package
changes:

```bash
./linux/scripts/verify-workstation.sh
```

It checks Plasma/SDDM, `/data`, core packages and commands, services, portals,
Docker configuration, SSH agent state, displays, and failed units. It does not
start services, connect the VPN, access secrets, or change machine state.

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
- `setup-display.sh` is retained only for its old X11 connector layout and
  refuses to run on Wayland. Configure the current displays through Plasma
  System Settings; KScreen preserves their geometry and scaling.

## SSH & Shell Configuration

The Linux Zsh configuration sources the shared
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
`HADES_SSH_HOST` (e.g. `oliver@192.168.68.108`) or `HADES_TUNNEL_PORTS` to
override the defaults.


- **SSH Agent**: Automatically start the agent and add keys in `~/.zshrc`:
  ```bash
  # Make sure the ssh keys are in
  # Start ssh-agent if not running
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)" > /dev/null
  fi

  # Add keys if not already added
  ssh-add -l >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed25519_ardis ~/.ssh/id_ed25519_github
  ```
