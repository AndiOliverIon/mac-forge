# AGENTS.md

## Purpose

`mac-forge` is a personal macOS automation workspace for Andi Ion Oliver.

It is not a single application. It is a toolbox of Bash scripts, aliases, and JSON configuration used to:

- manage a local SQL Server 2022 Docker workflow on macOS;
- switch active SQL storage and snapshot locations;
- restore, snapshot, clear, and administer development databases;
- support day-to-day work on Ardis/Perform repositories;
- automate local machine maintenance tasks such as file organization, shortcut cleanup, and utility helpers.

The repo is effectively an operational control center for this machine and its development environment.

## High-Level Layout

- `scripts/`: executable workflows and utilities.
- `configs/work-state.json`: active machine state for Docker SQL paths, organizer rules, and destination lists.
- `dotfiles/aliases`: shell command surface that exposes most repo functionality.
- `profiles/`: optional shell/profile presets.
- `config-local/`: local-only machine-specific state if present.

## Core Architecture

### Forge runtime

`scripts/forge.sh` is the central shared runtime. Most important scripts source it first.

It defines:

- machine and repo paths;
- SQL container defaults such as container name, image, port, and mount roots;
- iCloud secret-file location;
- derived active paths loaded from `configs/work-state.json`.

### Active state

`configs/work-state.json` is the main mutable state file.

It currently controls:

- active SQL Docker data path;
- active SQL snapshot path;
- known storage location presets;
- organizer folder categories;
- folders to organize;
- station destination presets.

This file is operational state, not just documentation.

### Main workflow model

This repo is centered around a cyclical DB workflow:

1. Select active storage with `scripts/work.sh`.
2. Start or ensure SQL/Docker environment.
3. Restore a `.bak` into the `forge-sql` SQL Server container.
4. Work locally against that DB.
5. Snapshot if needed.
6. Clear the environment when done.

The default SQL container identity used by the scripts is:

- container: `forge-sql`
- user: `sa`
- port: `2022`
- image: `mcr.microsoft.com/mssql/server:2022-latest`

## Important Scripts

- `scripts/forge.sh`: shared environment and state loader.
- `scripts/work.sh`: switches the active Docker and snapshot paths in `configs/work-state.json`.
- `scripts/db-restore.sh`: ensures SQL container availability and restores a selected `.bak`.
- `scripts/db-snapshot.sh`: creates DB snapshots/backups.
- `scripts/db-clear.sh`: soft or hard cleanup of databases/container/data.
- `scripts/db-admin.sh`: launches DB admin tooling.
- `scripts/docker-start.sh`: starts stopped Docker containers.
- `scripts/organizer.sh`: organizes files from configured folders by extension rules.
- `scripts/help.sh`: interactive launcher over aliases and scripts.
- `scripts/info.sh`: machine health snapshot.
- `scripts/perform-prep.sh`, `scripts/ardis-migrate.sh`, `scripts/gen-open-api.sh`: work-specific Ardis/Perform helpers.

## What Matters When Working Here

- This repo can affect live local machine state, not just source code.
- Some scripts touch Docker containers, mounted volumes, snapshots, Desktop/Downloads content, and mounted external/network storage.
- Secrets may be sourced from `~/Library/Mobile Documents/com~apple~CloudDocs/forge/forge-secrets.sh`.
- Several workflows assume macOS and tools like `docker`, `fzf`, `python3`, `sqlcmd`, `open`, and Homebrew-managed binaries.

## Agent Operating Rules

### General

- Prefer reading existing scripts and config before proposing structural changes.
- Treat this repo as operational tooling; preserve existing workflows unless the user asks to redesign them.
- Keep shell scripts simple, explicit, and compatible with the existing Bash-oriented style.
- Prefer targeted changes over broad refactors.

### Config and secrets safety

- Never print or expose secret values from the forge secrets file.
- Do not overwrite `configs/work-state.json` casually; it represents active machine state.
- If a task would change active storage paths, organizer behavior, or destructive cleanup behavior, call that out clearly.
- Be cautious with scripts that delete files, clear SQL data, or modify mounted storage.

### Git rules

- Git commands are allowed when they do not affect the online repository.
- Safe-by-default examples include: `git status`, `git diff`, `git log`, `git show`, `git branch`, and other local inspection commands.
- Local-only branch or workspace operations are allowed when they do not publish, rewrite shared history, or alter the remote state.
- Do not run commands that affect the online repository unless the user explicitly instructs it.
- Remote-affecting commands include, at minimum: `git push`, `git pull`, `git fetch`, remote branch deletion, PR merge flows, and any command that updates or depends on remote repository state.
- Never assume permission for commits, rebases, resets, stashes, or remote operations. If such an action is materially useful, ask first unless the user explicitly requested it.

### Editing guidance

- Match the existing repo style and keep comments sparse.
- Prefer updating documentation when behavior or workflow meaning changes.
- If changing a script with destructive behavior, preserve or improve confirmations and safety checks.
- When a task depends on machine-specific paths, document assumptions instead of hardcoding new ones without reason.

## Default Familiarity Summary

When starting work in this repo, assume the following:

- the repo is a macOS developer operations toolbox;
- the primary technical concern is a Dockerized SQL Server workflow with switchable storage roots;
- `forge.sh` and `work-state.json` are the core context files;
- aliases in `dotfiles/aliases` are part of the public interface of this repo;
- Ardis/Perform support scripts are important but secondary to the shared Forge runtime;
- safety matters more than cleverness because changes can affect the machine, databases, and mounted storage immediately.
