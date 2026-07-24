# Linux Fresh Install Checklist

A list of essential tools and configurations for a fresh Linux installation.

## Bootstrap

Run the workstation bootstrap from the repository root:

```bash
./linux/scripts/bootstrap.sh
```

The script installs the core development tools, IDEs, terminal, shell, and
Powerlevel10k setup used on a fresh Ubuntu workstation. It also installs `fzf`
and configures native Docker Engine with storage under `/data/docker`.

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

Use `sim` to cycle focus through the open, non-minimized applications captured
when the command starts:

```bash
sim
sim --cycle 30
```

The second form saves the interval in seconds. `sim` stays in the foreground
and unloads its temporary KWin script when stopped with `Ctrl+C`. It supports
Plasma on Wayland and X11 and requires one of `qdbus6`, `qdbus-qt6`, or
`qdbus`.

## Utilities
- **Flameshot**: Powerful screenshot tool.
    - *Note: Add the following to `~/.config/i3/config`:*
      ```bash
      # choice for screenshot screen
      bindsym Print exec flameshot gui -c
      ```

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
