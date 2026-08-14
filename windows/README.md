# Windows Forge workstation

The Windows layer keeps PowerShell as the interactive shell while reusing the
repository's shared Bash workflows through Git Bash. Native PowerShell is used
only for Windows profile, terminal, networking, and other platform operations.

## Bootstrap

From an elevated or normal PowerShell session in the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\windows\scripts\bootstrap.ps1
```

The bootstrap is repeatable. It:

- installs the workstation baseline with `winget`;
- installs the Windows-native Claude Code and GitHub Copilot CLI packages;
- installs global Node developer CLIs: Codex, Angular CLI, Yarn, and
  `vsts-npm-auth`;
- stages a Telerik license from `.telerik\telerik-license.txt`,
  `config-local\.telerik\telerik-license.txt`, or `TELERIK_LICENSE_SOURCE_DIR`
  when one is available;
- sets the current-user PowerShell execution policy to `RemoteSigned`;
- loads Forge from both Windows PowerShell and PowerShell 7 profiles;
- applies the shared minimal prompt through Oh My Posh;
- configures Windows Terminal with the Forge color scheme, transparency,
  padding, and JetBrainsMono Nerd Font;
- validates that the main Forge commands load.

Use these switches when only part of the setup is wanted:

```powershell
.\windows\scripts\bootstrap.ps1 -SkipPackages
.\windows\scripts\bootstrap.ps1 -SkipGlobalTools
.\windows\scripts\bootstrap.ps1 -SkipLicense
.\windows\scripts\bootstrap.ps1 -SkipTerminal
.\windows\scripts\bootstrap.ps1 -WhatIf
```

Windows Terminal creates its settings file on first launch. If terminal setup
is skipped with a warning, launch Terminal once and run:

```powershell
.\windows\scripts\configure-terminal.ps1
```

The terminal configurator creates a timestamped settings backup before writing.

## Command model

[profile.ps1](profile.ps1) loads [aliases.ps1](aliases.ps1) in every terminal.
PowerShell functions preserve familiar macOS/Linux names and forward arguments
to shared scripts:

```powershell
switch
dnc --dry-run
genopenapi
v1sn daily
v1list
```

Run `help` for common commands or `aliases` to inspect the complete surface.

Use `winget-update` to run Windows package updates listed in
`config-local\winget.json`. The file is local to the station; each non-empty,
non-comment line is appended to `winget update`.

## Local LAN Codex profile

Copy the secure `llm cli deploy` bundle to a station, open PowerShell in that
folder, then run `codex-local-register`. The command trusts the bundled local
certificate for the current user and creates the `local-lan` Codex profile.
Use `codex --profile local-lan` afterwards, or append `--verify` during
registration to make one test request. The bundle contains an API key and must
not be committed, emailed, or left on shared storage.

The launcher automatically:

- finds Git Bash;
- runs the script from the checked-out repository;
- exposes the Windows station name as `FORGE_MACHINE_NAME`;
- exposes the actual checkout as `FORGE_ROOT`;
- uses `config-local\forge-secrets.sh` when present.

Do not commit `config-local`; it is ignored and may contain private values.

## Development tool parity

The Windows bootstrap is intended to give Thanatos the same terminal flavor as
the macOS and Linux stations for daily .NET, Angular, SQL, Docker, Git, AI CLI,
and VPS1 work.

Installed by bootstrap:

- PowerShell 7, Windows Terminal, Git Bash, Oh My Posh, JetBrainsMono Nerd Font;
- ripgrep, fzf, jq, Python, Node.js LTS, Yarn `1.22.22`, Angular CLI `20.3.16`;
- GitHub CLI, GitHub Copilot CLI, Codex CLI, Claude Code;
- SQL Server `sqlcmd`, VS Code, Rider, Docker Desktop;
- .NET SDK 8, 9, and 10.

Manual station-local setup still required:

- authenticate `gh`, `copilot`, `codex`, and `claude`;
- make `ssh vps1`, `ssh oliver@masterchief`, and `ssh oliver@thanatos` work;
- configure user-level `.npmrc` or run `vsts-npm-auth` for private Azure
  Artifacts packages;
- verify commercial UI licenses from the relevant Angular client, for example
  `npx kendo-ui-license activate`;
- install or provide `rsync` before using VPS1 transfer commands such as
  `v1up`, `v1down`, and `rdown-to-v1`.

## Native Windows commands

SSH tunnels use a common PowerShell implementation because the Unix tunnel
scripts depend on process and socket tools not supplied by Git Bash:

```powershell
v1-sql-tunnel-up
v1-license-tunnel-up
v1-bl-tunnel-up
v1-meerkat-tunnel-up
v1-tally-tunnel-up
```

Each has matching `down` and `status` commands and long-form `vps1-*` aliases.
The existing SQL `.cmd` launchers remain available.

The SSH host alias `vps1` and key authentication must already work:

```powershell
ssh vps1
```

SQL clients connect through `localhost,14333`.

### Hades development tunnel

When the Angular and Perform API development servers run on Hades, expose them
only to the Windows guest through the Hades SSH tunnel:

```powershell
hades-tunnel-up
hades-tunnel-status
hades-tunnel-down
```

While the tunnel is up, Windows reaches the Hades services at
`http://localhost:4200` and `http://localhost:8080`. Hades must have Remote
Login enabled and key-based SSH access must work from Windows. The tunnel uses
`oliver@10.211.55.2` and `~/.ssh/id_ed25519_hades_tunnel` by default; set
`HADES_SSH_HOST` or `HADES_SSH_IDENTITY_FILE` to override them.

## Shared versus station-specific state

The shared Bash runtime now derives the repository root from its own location
and accepts `FORGE_MACHINE_NAME`, `FORGE_ROOT`, and `FORGE_SECRETS_FILE`
overrides.

`configs/work-state.json` still describes Hades paths under `/Users` and
`/Volumes`. Windows does not automatically expose destructive or stateful local
Docker/storage commands that consume those paths. Those workflows need a
station-local state contract before they are safe to enable on Windows.

Commands backed primarily by Git, source files, build tools, SSH, or VPS1 are
shared now. Commands involving macOS applications, mounted volumes, display
management, VPN process management, or Hades storage remain platform-specific.

OneDrive/iCloud, Google Drive, and Cerber navigation or synchronization aliases
remain macOS-only and are intentionally not registered in PowerShell.
