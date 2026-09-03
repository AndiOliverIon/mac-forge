# Architecture Scope

Read this file when working on Forge runtime, `configs/work-state.json`, SQL/Docker behavior, storage
switching, snapshots, or database workflow scripts.

## High-Level Layout

- `scripts/`: executable workflows and utilities.
- `scripts/vps1/`: default shared VPS1 database, tunnel, and deployment helpers.
- `configs/work-state.json`: mutable local operational state, including the Hades-local database
  fallback, organizer rules, and destination lists.
- `configs/stations.json`: canonical non-secret station, VM, server, and attached-device inventory.
- `config-local/stations.json`: ignored overlay for sensitive station identifiers and networking.
- `config-local/local-store.json`: ignored local connection store, including the VPS1 SQL profile.
- `dotfiles/aliases`: primary operator command surface; `dotfiles/aliases-vps1` exposes VPS1 helpers.
- `profiles/`: optional shell/profile presets.

## Cross-Platform Shared Configuration

Configuration shared across station architectures lives in a neutral location, with station-local
paths symlinked to the tracked source instead of divergent copies.

- `dotfiles/ghostty.ghostty` is shared by macOS and Linux. Linux bootstrap links it to
  `~/.config/ghostty/config.ghostty`; `scripts/configure-ghostty.sh` links it to Ghostty's macOS path
  and also links the shared zsh and Powerlevel10k profiles. Its login-shell default is OS-agnostic;
  `macos-titlebar-style` is harmlessly ignored on Linux. Windows is not covered yet.
- `.config/ai` is the shared Artanis, Argus, and Aegis instruction source. Unix stations expose it at
  `~/.config/ai`; tool-owned `~/.codex` and `~/.claude` directories remain physical. Use
  `scripts/ai-config.sh` to verify, install, or fast-forward-sync the shared configuration.

## Runtime and State Authorities

- `scripts/vps1/vps1.sh` supplies the default database connection, tunnel, SQL, SSH, snapshot, and
  safety helpers used by `scripts/vps1/vps1-db-*`.
- `scripts/forge.sh` supplies shared machine/repository paths and the older local workflow's Docker
  defaults and derived paths.
- `configs/work-state.json` is operational state, not documentation. Its Docker paths and storage
  presets govern only the Hades-local database fallback; it also governs clean targets, organizer
  categories/folders, station destinations, and other local workflow values.
- Secret connection values come from ignored local configuration. Never print, copy into tracked
  files, or hardcode them.

## Docker Database Model

VPS1 is the default Docker-hosted development database for Hades, Cerber, and MasterChief. Clients
use their established private connection or tunnel; they do not assume a local SQL container merely
because a Docker daemon is present.

The Mac Forge VPS1 workflow uses local `sqlcmd` through the managed tunnel and SSH/rsync for remote
files. Prefer the established `scripts/vps1/vps1-db-*` helpers and `v1*` aliases over ad-hoc remote
commands. Verify the selected host, database, and operation before mutations.

Hades retains a rarely used local Docker SQL fallback. Its details live in
`~/.config/ai/guidelines/stacks/docker-db-local-fallback.md` and must not be loaded unless `ops.md`
selects that fallback. Existing local database scripts and `work-state.json` Docker fields are
compatibility mechanisms, not the normal database route.

General Docker work—image builds, application containers, Compose, and cleanup unrelated to the
development database—may still run locally and is not redirected to VPS1 by this rule.

## Important Scripts

- `scripts/vps1/vps1.sh`: shared VPS1 connection and operation helpers.
- `scripts/vps1/vps1-db-*`: list, migrate, restore, snapshot, upload/download, optimize, index,
  state, and destructive database workflows on VPS1.
- `scripts/vps1/vps1-sql-tunnel.sh`: private local-to-VPS1 SQL tunnel.
- `scripts/forge.sh`, `scripts/work.sh`, and `scripts/db-*`: local operational and fallback helpers.
- `scripts/organizer.sh`: organizes configured folders by extension rules.
- `scripts/help.sh`: interactive launcher over aliases and scripts.
- `scripts/info.sh` and `scripts/vps1-status`: local and VPS1 health views.
- `scripts/ai-config.sh`: verifies, installs, and synchronizes shared AI instructions.
- `scripts/clean.sh`: interactive cleaner for configured target directories.
- `scripts/perform-prep.sh`, `scripts/perform-test.sh`, `scripts/ardis-migrate.sh`, and
  `scripts/gen-open-api.sh`: Ardis/Perform helpers.

## Operational Priorities

- Treat VPS1 as the normal database authority and local SQL as an explicit contingency.
- Safety matters more than cleverness because operations can affect databases, remote services, and
  mounted storage immediately.
- Preserve confirmations and verify outcomes around destructive or privileged operations.
- Inspect the relevant scripts and live configuration rather than relying only on this overview.
