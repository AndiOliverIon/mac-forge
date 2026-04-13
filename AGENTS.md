# AGENTS.md

## Purpose

`mac-forge` is a personal macOS operations toolbox for Andi Ion Oliver. It manages local SQL Server Docker workflows, station automation, aliases, and machine-maintenance scripts.

## Always-read rules

- Lead with the direct answer or outcome. Keep responses short, precise, and free of filler, recap, praise, or conversational padding. Add detail only when it materially improves correctness, clarity, or safety.
- Read existing scripts and config before proposing or making structural changes.
- Treat this repo as operational tooling; preserve existing workflows unless the user asks to redesign them.
- Prefer targeted changes over broad refactors.
- Keep shell scripts simple, explicit, and compatible with the existing Bash-oriented style.
- Always check `configs/work-state.json` when investigating Docker paths, station metadata, or other active machine state.

## Safety rules

- Never print or expose secret values from the forge secrets file.
- Do not overwrite `configs/work-state.json` casually; it represents active machine state.
- If state already exists in `configs/work-state.json`, prefer reading it from there instead of hardcoding duplicate values in scripts.
- If a task would change active storage paths, station behavior, organizer behavior, or destructive cleanup flows, call that out clearly.
- Do not introduce silent changes to active paths, station behavior, or destructive cleanup behavior; document them when behavior meaning changes.
- Be cautious with scripts that delete files, clear SQL data, or modify mounted storage.

## Git rules

- Git commands are allowed when they do not affect the online repository.
- Safe-by-default examples include `git status`, `git diff`, `git log`, `git show`, and `git branch`.
- Do not run remote-affecting commands unless the user explicitly instructs it.
- Never assume permission for commits, rebases, resets, stashes, or other history-changing operations.

## Task-based reading map

Read the additional file that matches the work you are doing. If a task spans multiple areas, read all relevant files before acting.

- `agents/architecture.md` — read when touching Forge runtime, `work-state.json`, SQL/Docker workflow, storage switching, snapshots, or database helper scripts.
- `agents/stations.md` — read when touching station metadata, SSH aliases, sleep/shutdown/boot flows, Wake-on-LAN, or network-topology-sensitive behavior.
- `agents/interfaces.md` — read when changing `dotfiles/aliases`, Linux alias parity, or any high-frequency user-facing command surface.
- `agents/preferences.md` — read when the task involves machine setup, tool installation, operator preferences, or Hades-specific environment choices.

## Editing rules

- Match the existing repo style and keep comments sparse.
- Prefer updating documentation when behavior or workflow meaning changes.
- When changing a user-facing alias in `dotfiles/aliases`, update the corresponding Linux alias file too when that command surface exists there.
- Treat aliases and high-frequency scripts as a public interface; preserve backward-compatible names where practical when refining behavior.
- Keep station power commands explicitly separated by intent (`sleep`, `shutdown`, `boot`) and never use a sleep alias to perform a shutdown.
- If changing a script with destructive behavior, preserve or improve confirmations and safety checks.
- When a task depends on machine-specific paths, document assumptions instead of hardcoding new ones without reason.
