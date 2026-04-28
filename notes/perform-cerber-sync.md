# Parallels Windows Mirror Workflow Notes

## Goal

Set up a macOS-first development workflow where the main working copy remains on macOS and a fast Windows-local mirror exists inside the Parallels VM.

- macOS working copy: `/Users/oliver/work/ardis-perform`
- Windows mirror copy: `C:\work\ardis-perform`
- Windows Visual Studio should open the Windows-local mirror, not a Parallels shared folder.
- Avoid git push/pull ping-pong between macOS and Windows.
- Use explicit Hades-controlled directional sync commands, not automatic/live sync.

## Current Decisions

- Use `C:\work\...` on Windows, matching the macOS `work` naming convention.
- Use SSH from macOS into the Windows VM.
- Default Git decision: do not sync `.git/` unless later proven safe and necessary.
- Hades/macOS remains the primary Git authority.
- Updated workflow decision: synchronization should be manual and directional, not automatic/live.
- Desired commands:
  - `h2c`: Hades/macOS -> Cerber/Windows.
  - `c2h`: Cerber/Windows -> Hades/macOS.
- Before either direction, the user will make sure both working copies are on the same branch.
- Cerber works with whatever macOS explicitly provides, then macOS explicitly pulls the changed working tree back when requested.
- Because of this, Mutagen's live bidirectional sync is not the preferred workflow. A command-triggered directional sync tool is a better fit.

## Discovery Results

Captured on 2026-04-27 from macOS.

- macOS architecture: Apple Silicon / `arm64`.
- Project root: `/Users/oliver/work/ardis-perform`.
- Project size: approximately `5.2G`.
- Git state at discovery time: clean (`git status --short` produced no output).
- Homebrew is installed at `/opt/homebrew/bin/brew`.
- Mutagen is not currently installed.
- Parallels CLI is installed at `/usr/local/bin/prlctl`.
- Windows VM name: `Windows 11`.
- Windows VM state: running.
- Windows guest OS: Windows 11 ARM (`win-11`, `efi-arm64`, CPU type `arm`).
- Parallels Tools: installed, version `26.3.1-57396`.
- Parallels networking mode: shared/NAT (`net0 type=shared`).
- Windows IPv4 reported by Parallels: `10.211.55.3`.
- macOS can ping `10.211.55.3` successfully.
- TCP port 22 did not respond promptly from macOS, so Windows OpenSSH Server is probably not listening yet or the firewall blocks it.
- Existing macOS SSH config contains GitHub/GitLab/Bitbucket entries only; no Windows VM host alias yet.
- Existing macOS SSH keys are present. We should decide whether to reuse `~/.ssh/id_ed25519.pub` or create a dedicated VM key.
- Windows identity from VM PowerShell:
  - User: `oliver`
  - UserDomain: `CERBER`
  - ComputerName: `CERBER`
- Windows OpenSSH Server capability was initially `NotPresent`.
- `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` completed successfully and reported `RestartNeeded: False`.
- `C:\work\ardis-perform` was created successfully.
- `sshd` service was configured with `sc.exe config sshd start= auto`.
- `sshd` was started successfully and listened on:
  - `0.0.0.0:22`
  - `[::]:22`
- Windows firewall rule `OpenSSH Server (sshd)` was created successfully using `netsh`.
- Windows `ipconfig` confirmed IPv4 address `10.211.55.3`.
- macOS SSH reached the Windows VM but key authentication failed:
  - Command: `ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new oliver@10.211.55.3 hostname`
  - Result: `Permission denied (publickey,password,keyboard-interactive).`
- Next required fix: repair/confirm Windows `authorized_keys` permissions and also add the key to `C:\ProgramData\ssh\administrators_authorized_keys`, because Windows OpenSSH often uses that file for users in the local Administrators group.
- Windows SSH key auth fix:
  - User key path: `C:\Users\oliver\.ssh\authorized_keys`
  - Admin key path: `C:\ProgramData\ssh\administrators_authorized_keys`
  - The macOS public key was added to both locations.
  - ACLs were repaired with `icacls.exe`.
  - `sshd` was restarted.
- macOS SSH key auth now works:
  - Command: `ssh -o BatchMode=yes -o ConnectTimeout=5 oliver@10.211.55.3 hostname`
  - Result: `Cerber`
- macOS SSH config alias added:
  - File: `~/.ssh/config`
  - Host alias: `cerber-win`
  - HostName: `10.211.55.3`
  - User: `oliver`
  - IdentityFile: `~/.ssh/id_ed25519`
- SSH alias validation works:
  - Command: `ssh -o BatchMode=yes -o ConnectTimeout=5 cerber-win hostname`
  - Result: `Cerber`
- Mutagen was installed on macOS via Homebrew:
  - Command: `brew install mutagen-io/mutagen/mutagen`
  - Version: `0.18.1`
  - Homebrew installed the formula at `/opt/homebrew/Cellar/mutagen/0.18.1`.
- Mutagen daemon was started with:
  - `mutagen daemon start`
- A tiny smoke-test session was created successfully:
  - Session name: `ardis-mutagen-smoke`
  - Alpha: `/tmp/mutagen-smoke-test`
  - Beta: `cerber-win:C:/work/mutagen-smoke-test`
  - Mode: `two-way-safe`
  - Result: Windows agent installed successfully and session connected.
- Smoke-test validation:
  - macOS to Windows file sync worked.
  - Windows to macOS file sync worked.
  - Smoke-test session was terminated with `mutagen sync terminate ardis-mutagen-smoke`.
  - Smoke-test folders were removed from `/tmp/mutagen-smoke-test` and `C:\work\mutagen-smoke-test`.
- Important safety discovery:
  - `C:\work\ardis-perform` already exists and is not empty.
  - It contains a `.git` directory, so it is currently a separate Windows Git working copy.
  - Windows working copy status is clean (`git -C C:\work\ardis-perform status --short` produced no output).
  - macOS branch: `aoi/per-6384-report-bug-dev`.
  - macOS commit: `28b31379cb533af4120ce3283f26901336050f70`.
  - Windows branch: `main`.
  - Windows commit: `541bb6f0d46b049c8818fdb14927610b457d8fbc`.
  - Conclusion: do not start a two-way Mutagen session against the existing Windows folder as-is, because stale/different Windows files could sync back into the macOS working copy.
- Mutagen cleanup after workflow pivot:
  - Mutagen formula was uninstalled with `brew uninstall mutagen`.
  - Mutagen tap was removed with `brew untap mutagen-io/mutagen`.
  - macOS Mutagen state folder `/Users/oliver/.mutagen` was removed.
  - Windows Mutagen state folder `C:\Users\oliver\.mutagen` was removed.
- rclone setup:
  - Installed on macOS with `brew install rclone`.
  - Version at setup: `rclone v1.73.5`.
  - Config file: `/Users/oliver/.config/rclone/rclone.conf`.
  - Remote name: `cerber`.
  - Remote type: `sftp`.
  - Remote host: `10.211.55.3`.
  - Remote user: `oliver`.
  - Remote key file: `/Users/oliver/.ssh/id_ed25519`.
  - Remote shell type: `powershell`.
- mac-forge integration:
  - Script: `/Users/oliver/mac-forge/scripts/perform-cerber-sync.sh`.
  - Exclude rules: `/Users/oliver/mac-forge/configs/perform-cerber-sync-excludes.txt`.
  - Decision notes: `/Users/oliver/mac-forge/notes/perform-cerber-sync.md`.
  - Aliases:
    - `h2c-preview`: dry-run Hades -> Cerber.
    - `h2c`: sync Hades -> Cerber.
    - `c2h-preview`: dry-run Cerber -> Hades.
    - `c2h`: sync Cerber -> Hades.
- Validation:
  - `perform-cerber-sync.sh status` works and confirms both sides are on branch `aoi/per-6384-report-bug-dev`.
  - The first rclone whole-tree `h2c-preview` was intentionally replaced because it was too noisy and line-ending-sensitive.
  - The old whole-tree preview showed:
    - New files on target: `6270`.
    - Updates on target: `5872`.
    - Target-only files to backup/remove: `0`.
    - Read/compare errors: `0`.
    - Total changed paths: `12142`.
  - The active preview is now Git-status based.
  - `h2c-preview` now reads Hades `git status --porcelain=v1 --untracked-files=all` and reports only source working-tree changes.
  - `c2h-preview` now reads Cerber `git status --porcelain=v1 --untracked-files=all` and reports only source working-tree changes.
  - Validation after switching to Git-status mode:
    - `h2c-preview` showed one Hades change: `Ardis.Production.Business/Algorithms/FillBomReservations/FillBomReservationsCore.cs`.
    - `c2h-preview` showed no Cerber changes.
- Line-ending finding:
  - Hades repo config: `core.autocrlf=input`.
  - Cerber repo config: `core.autocrlf=true`.
  - This likely explains many byte-level differences in dry-run output even when both branches match.
  - Before the first real `h2c`, consider normalizing Cerber's repo config or accepting that the first sync may rewrite many text files on Cerber.
- Real sync behavior:
  - `h2c` runs immediately after showing the Git-status summary.
  - `c2h` runs immediately after showing the Git-status summary.
  - The command itself is treated as the user's explicit confirmation.
- Cerber cleanup after `c2h`:
  - After a successful `c2h`, the script runs `git reset --hard` and `git clean -fd` in `C:\work\ardis-perform` by default.
  - This makes Cerber disposable after it has done its job, so the next Windows session starts from a fresh `h2c` handoff.
  - Set `PERFORM_SYNC_CLEAN_CERBER_AFTER_DOWN=0` to leave Cerber dirty after `c2h`.
- Windows PowerShell management commands failed in the shell used:
  - `Set-Service`, `Start-Service`, and `Get-Service` failed with missing `System.ComponentModel.Primitives, Version=10.0.0.0`.
  - `Get-NetFirewallRule`/`New-NetFirewallRule` failed with cmdletization/object-reference errors.
  - `Get-NetIPAddress` reported that the `NetTCPIP` module could not be loaded.
- Interpretation: likely running in a newer/broken `pwsh` environment or profile/module issue. Next Windows step should use classic Windows PowerShell 5.1 (`powershell.exe`) or fallback commands such as `sc.exe`, `netsh`, and `ipconfig`.

Detected project/tooling signals:

- Main solution: `Asms2.Web.sln`.
- .NET projects: many `*.csproj` files across backend/shared/tooling folders.
- Node/package files: root `package.json`, root `package-lock.json`, root `yarn.lock`, and `ardis.perform.client/package.json`.
- Docker files: root `docker-compose.yml`, root `docker-compose.override.yml`, several files under `Docker/`, and `Asms2.Web/Dockerfile`.
- NuGet config: `nuget.config`.
- Generated/cache folders currently present include root `.git/`, `.vs/`, `bin/`, `obj/`, `dist/`, root `node_modules/`, `Asms2.Web/node_modules/`, and `ardis.perform.client/node_modules/`.

## Things We May Install Or Configure

### macOS

- rclone installed via Homebrew.
- SSH key access to Cerber.
- SSH host alias `cerber-win`.

### Windows VM

- OpenSSH Server Windows optional feature.
- `sshd` service configured to start automatically.
- Windows Firewall rule allowing inbound SSH on TCP port 22.
- `C:\work\ardis-perform` mirror directory.
- `authorized_keys` entry for the macOS public SSH key.

## Intended Mutagen Session

Earlier proposed session name:

```text
ardis-perform-win
```

Proposed sync mode:

```text
two-way-safe
```

Proposed endpoints:

```text
/Users/oliver/work/ardis-perform
ssh://<windows-user>@<windows-host>/C:/work/ardis-perform
```

The exact SSH endpoint may need adjustment after confirming Windows OpenSSH path behavior.

Note: after clarifying the desired workflow, a persistent automatic Mutagen session is no longer the preferred primary setup. Prefer explicit `sync-up` and `sync-down` commands instead.

This section is historical. The active workflow uses rclone directional sync.

## Initial Ignore Rules To Review

```gitignore
.git/
**/.git/
bin/
**/bin/
obj/
**/obj/
.vs/
**/.vs/
.vscode/
**/.vscode/
.idea/
**/.idea/
.claude/
.codex-notes/
.run/
TestResults/
**/TestResults/
*.user
*.suo
*.rsuser
*.ncrunch*
_ReSharper*/
node_modules/
**/node_modules/
dist/
**/dist/
build/
**/build/
coverage/
**/coverage/
.angular/
**/.angular/
.DS_Store
Thumbs.db
```

The active exclude file is `/Users/oliver/mac-forge/configs/perform-cerber-sync-excludes.txt`.
These rules are meant to keep rclone from spending time scanning generated/cache folders such as `bin`, `obj`, `node_modules`, `.angular`, and `.vs`.

## Validation Checklist

- Confirm macOS architecture.
- Confirm Parallels VM name, Windows hostname, and Windows IP.
- Confirm macOS can SSH into Windows VM.
- Confirm key-based SSH auth works.
- Confirm `C:\work\ardis-perform` exists.
- Start Mutagen session.
- Edit a harmless file on macOS and confirm it appears in Windows.
- Edit a harmless file on Windows and confirm it appears back on macOS.
- Confirm ignored folders such as `bin/`, `obj/`, `.vs/`, and `node_modules/` do not sync.
- Open Visual Studio using `C:\work\ardis-perform`.
- Confirm Visual Studio output/cache files remain ignored.
- Check conflict behavior with a deliberate small test file.

## Updated Recommended Workflow: Manual Directional Sync

The desired workflow is not a live bidirectional mirror. It is a manual handoff model:

1. Work normally on macOS.
2. When Windows is needed, make sure both macOS and Windows checkouts are on the same branch.
3. Run a Hades-controlled `h2c-preview`, then `h2c` command:
   - Source: `/Users/oliver/work/ardis-perform`
   - Destination: `cerber:C:/work/ardis-perform`
4. Work in Visual Studio on Windows.
5. Run a Hades-controlled `c2h-preview`, then `c2h` command:
   - Source: `cerber:C:/work/ardis-perform`
   - Destination: `/Users/oliver/work/ardis-perform`

Recommended tool for this updated workflow:

- Prefer `rclone` over Mutagen for the actual day-to-day commands.
- Reason: `rclone sync` can use SFTP over the already configured Windows OpenSSH Server and does not require a remote `rsync` binary on Windows.
- Mutagen was proven functional, then removed because its normal value is continuous/live synchronization, which no longer matches the desired workflow.

Planned safety defaults:

- Exclude `.git/` in both directions.
- Keep Git operations branch-aware and manual on both systems.
- Use preview/dry-run commands before destructive syncs when desired.
- Consider backup directories for overwritten/deleted files during the first few real runs.
- Do not run sync-up if Windows has unsaved work that has not been synced down.
- Do not run sync-down if macOS has independent edits made after the last sync-up.

Active command names:

- `h2c-preview`
- `h2c`
- `c2h-preview`
- `c2h`

Preview output:

- `h2c-preview` and `c2h-preview` are Git-status based, not whole-tree rclone comparisons.
- They print counts for:
  - files to copy/update,
  - files to delete on the target.
- They then print the Git-status actions, capped by `PERFORM_SYNC_PREVIEW_LIMIT` (default `120`).
- Generated and ignored folders such as `bin`, `obj`, `.vs`, `.angular`, and `node_modules` are skipped because they are not part of normal Git status.

## Rollback Plan

### Stop Or Remove Mutagen Session

Check sessions:

```bash
mutagen sync list
```

Pause session:

```bash
mutagen sync pause ardis-perform-win
```

Terminate session:

```bash
mutagen sync terminate ardis-perform-win
```

### Remove Windows Mirror

Only after confirming there is no unsynced work in `C:\work\ardis-perform`:

```powershell
Remove-Item -LiteralPath 'C:\work\ardis-perform' -Recurse -Force
```

### Disable Windows OpenSSH Server

If OpenSSH Server was enabled only for this experiment:

```powershell
Stop-Service sshd
Set-Service -Name sshd -StartupType Disabled
```

Optional uninstall:

```powershell
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

### Remove Windows Firewall Rule

If we created a dedicated SSH firewall rule:

```powershell
Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
```

The actual rule name must be confirmed before running removal.

### Remove macOS SSH Alias

If we add an entry to `~/.ssh/config`, remove the matching `Host ...` block.

### Remove macOS SSH Key

Only if a dedicated key was created for this experiment and is not used elsewhere:

```bash
rm ~/.ssh/<dedicated-key-name> ~/.ssh/<dedicated-key-name>.pub
```

Do not remove existing shared SSH keys.

### Uninstall Mutagen From macOS

If installed with Homebrew:

```bash
brew uninstall mutagen-io/mutagen/mutagen
```

The exact formula command should be confirmed at install time.

## Current Manual Workflow

We replaced live Mutagen sync with command-driven, Git-status-based sync.

Profiles live in:

```text
/Users/oliver/mac-forge/configs/hades-cerber-sync.json
```

Current aliases:

```bash
h2c -help
h2c perf
h2c-preview perf
c2h perf
c2h-preview perf
```

`h2c` means Hades to Cerber. `c2h` means Cerber to Hades.

`h2c <profile>` prepares Cerber before copying files:

1. Confirm the Cerber working tree is clean.
2. Fetch the configured base branch, for example `origin/development`.
3. Recreate the Cerber branch with the same name as the current Hades branch from that base branch.
4. Copy only Hades Git working-tree changes to Cerber.
5. Always copy selected Hades-owned local override files to Cerber.
6. Apply Cerber-local Visual Studio fixes for PERFORM profiles.

This means Cerber is disposable. If Cerber has uncommitted changes, the flow stops and asks for the VM checkout to be cleaned/reset first.

The Cerber Git commands run with `GIT_TERMINAL_PROMPT=0` and a non-interactive `GIT_SSH_COMMAND`, because plain Windows `git fetch` can wait forever behind SSH or credential prompts that are invisible from the macOS terminal.

The `perf` and `perf230` profiles also promote these local override folders from Hades to Cerber on every `h2c`:

```text
Ardis.Perform.UnitTest/Helpers/MockLicenseService.cs
local-overrides
Asms2.Web/local-overrides
```

Those override paths are Hades-owned in this workflow, so `c2h` ignores Cerber-side changes under them.

`c2h <profile>` copies Cerber Git working-tree changes back to Hades and then cleans Cerber when the profile says `afterC2h: "clean"`.

For code that was originally copied from Hades during `h2c`, `c2h` compares Cerber's current file hash with the Hades-origin baseline. If the file is unchanged from what `h2c` copied, it is skipped. If Cerber changed the code, `c2h` brings that changed file back to Hades.

## Current Profiles

```text
perf
  Hades:  /Users/oliver/work/ardis-perform
  Cerber: cerber:C:/work/ardis-perform
  Base:   origin/development

perf228
  Hades:  /Users/oliver/work/ardis-perform-228
  Cerber: cerber:C:/work/ardis-perform-228
  Base:   origin/release/2.28

perf230
  Hades:  /Users/oliver/work/ardis-perform-230
  Cerber: cerber:C:/work/ardis-perform-230
  Base:   origin/release/2.30
```

PERFORM profiles also create a Cerber-only `Asms2.Web.cerber.sln`, strip Visual Studio Docker tooling from the Cerber-local project files, and ensure `Asms2.Web.csproj` compiles `../local-overrides/**/*.cs` after `h2c`, because Visual Studio hangs in this Parallels VM when its container tooling inspects this solution and the local override mock license lives outside the web project folder.

Those Cerber-local files are ignored by `c2h`, so the Docker-tooling strip should not come back to Hades.

## Open Questions

- Exact Windows VM hostname/IP.
- Whether Parallels networking is shared/NAT or bridged.
- Whether Windows OpenSSH Server is already installed.
- Whether a stable hostname is available from macOS.
- Whether Visual Studio/project tooling needs access to Git metadata.
- Whether any repo-specific generated folders need additional ignore rules.

## Next Step

Decide how to handle the existing `C:\work\ardis-perform` working copy before creating the real Mutagen session.

Recommended safe path:

1. Rename the existing Windows folder to a timestamped backup, for example `C:\work\ardis-perform.before-mutagen-20260427-1328`.
2. Create a fresh empty `C:\work\ardis-perform`.
3. Create the real Mutagen session from macOS to that empty folder with `--ignore-vcs` and the reviewed ignore rules.
4. Keep the backup folder temporarily until the new mirror is validated in Visual Studio.
