# Architecture scope

Read this file when working on Forge runtime, `configs/work-state.json`, SQL/Docker behavior, storage switching, snapshots, or database workflow scripts.

## High-level layout

- `scripts/`: executable workflows and utilities.
- `configs/work-state.json`: active machine state for Docker SQL paths, organizer rules, station metadata, and destination lists.
- `dotfiles/aliases`: shell command surface that exposes most repo functionality.
- `profiles/`: optional shell/profile presets.
- `config-local/`: local-only machine-specific state if present.

## Forge runtime

`scripts/forge.sh` is the central shared runtime. Most important scripts source it first.

It defines:

- machine and repo paths;
- SQL container defaults such as container name, image, port, and mount roots;
- iCloud secret-file location;
- derived active paths loaded from `configs/work-state.json`.

## Active state

`configs/work-state.json` is the main mutable state file.

It currently controls:

- active SQL Docker data path;
- active SQL snapshot path;
- known storage location presets;
- organizer folder categories;
- folders to organize;
- station metadata such as IP, MAC, and OS;
- station destination presets.

This file is operational state, not just documentation.

## Main workflow model

This repo is centered around a cyclical DB workflow:

1. Select active storage with `scripts/work.sh`.
2. Start or ensure SQL/Docker environment.
3. Restore a `.bak` into the `forge-sql` SQL Server container.
4. Work locally against that DB.
5. Snapshot if needed.
6. Clear the environment when done.

Default SQL container identity:

- container: `forge-sql`
- user: `sa`
- port: `2022`
- image: `mcr.microsoft.com/mssql/server:2022-latest`

## Important scripts

- `scripts/forge.sh`: shared environment and state loader.
- `scripts/work.sh`: switches the active Docker and snapshot paths in `configs/work-state.json`.
- `scripts/db-restore.sh`: ensures SQL container availability and restores a selected `.bak`.
- `scripts/db-snapshot.sh`: creates DB snapshots/backups.
- `scripts/db-clear.sh`: soft or hard cleanup of databases, container, and data.
- `scripts/db-admin.sh`: launches DB admin tooling.
- `scripts/docker-start.sh`: starts stopped Docker containers.
- `scripts/organizer.sh`: organizes files from configured folders by extension rules.
- `scripts/help.sh`: interactive launcher over aliases and scripts.
- `scripts/info.sh`: machine health snapshot.
- `scripts/perform-prep.sh`, `scripts/ardis-migrate.sh`, `scripts/gen-open-api.sh`: work-specific Ardis/Perform helpers.

## Operational context

- This repo is a macOS developer operations toolbox.
- The primary technical concern is a Dockerized SQL Server workflow with switchable storage roots.
- `forge.sh` and `work-state.json` are the core context files.
- Ardis/Perform support scripts are important but secondary to the shared Forge runtime.
- Safety matters more than cleverness because changes can affect the machine, databases, and mounted storage immediately.
- Several workflows assume macOS and tools like `docker`, `fzf`, `python3`, `sqlcmd`, `open`, and Homebrew-managed binaries.
