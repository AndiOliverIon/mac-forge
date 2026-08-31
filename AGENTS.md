# AGENTS.md

## Purpose

`mac-forge` is a personal macOS operations toolbox for Andi Ion Oliver. It manages local SQL Server Docker workflows, station automation, aliases, and machine-maintenance scripts.

## Agent identities

- **Artanis** is the primary Codex coworker and implementation partner.
- **Raynor** is a MasterChief worker agent with an isolated universe at
  `/home/oliver/raynor`.
- **Zeratul** is a MasterChief worker agent with an isolated universe at
  `/home/oliver/zeratul`.
- MasterChief has a hard concurrency limit of two agents total: Raynor and
  Zeratul may work in parallel, but a third agent must never be started there.
- These universes are ordinary directories owned by the `oliver` Linux account,
  not separate Linux user homes or accounts.
- Raynor must keep all agent work inside `/home/oliver/raynor` and must never
  inspect or modify `/home/oliver/zeratul`. Zeratul has the inverse boundary.
  An agent must use only the identity assigned to its current universe.

## Always-read rules

- Lead with the direct answer or outcome. Keep responses short, precise, and free of filler, recap, praise, or conversational padding. Add detail only when it materially improves correctness, clarity, or safety.
- Read existing scripts and config before proposing or making structural changes.
- Treat this repo as operational tooling; preserve existing workflows unless the user asks to redesign them.
- Prefer targeted changes over broad refactors.
- Keep shell scripts simple, explicit, and compatible with the existing Bash-oriented style.
- Always check `configs/stations.json` when investigating station or attached-device metadata and
  `configs/work-state.json` when investigating Docker paths or other active
  machine state. Sensitive station network facts are stored only in the ignored
  `config-local/stations.json` overlay.

## Safety rules

- Never print or expose secret values from the forge secrets file.
- Never commit values from `config-local/stations.json`; it holds sensitive
  station identifiers and network addressing referenced by the public station
  inventory.
- Do not overwrite `configs/work-state.json` casually; it represents active machine state.
- If operational state already exists in `configs/work-state.json`, prefer
  reading it from there instead of hardcoding duplicate values in scripts. If
  station metadata exists in `configs/stations.json`, treat that inventory as
  canonical.
- If a task would change active storage paths, station behavior, organizer behavior, or destructive cleanup flows, call that out clearly.
- Do not introduce silent changes to active paths, station behavior, or destructive cleanup behavior; document them when behavior meaning changes.
- Be cautious with scripts that delete files, clear SQL data, or modify mounted storage.

## Git rules

- Git commands are allowed when they do not affect the online repository.
- Safe-by-default examples include `git status`, `git diff`, `git log`, `git show`, and `git branch`.
- Work directly on `main` and commit and push completed scoped changes by
  default unless the user explicitly requests a separate branch or asks not to
  push.
- Do not create feature branches by default in this personal repository.
- Never assume permission for rebases, resets, stashes, or destructive history
  changes.

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
