# AGENTS.md

## Purpose

`mac-forge` is a personal operations toolbox for Andi Ion Oliver. It manages shared VPS1 database
workflows, a Hades-local database fallback, station automation, aliases, and machine-maintenance
scripts.

## Always-read rules

- Read existing scripts and config before proposing or making structural changes.
- Treat this repo as operational tooling; preserve existing workflows unless the user asks to redesign them.
- Prefer targeted changes over broad refactors.
- Keep shell scripts simple, explicit, and compatible with the existing Bash-oriented style.

## Configuration sources

- `configs/work-state.json` is canonical local operational state, including the Hades-local database
  fallback. Inspect it for relevant local/path work; never overwrite it casually or hardcode its
  values in scripts.
- `configs/stations.json` is the canonical non-secret station and attached-device inventory.
- `config-local/stations.json` is the ignored overlay for sensitive station identifiers and network
  addressing. Never expose or commit its values.
- `config-local/local-store.json` is the ignored local connection store, including VPS1 SQL secrets.
  Never expose or commit its values.

## Safety rules

- Never print or expose secret values from the forge secrets file.
- Call out and document behavior changes affecting active storage paths, stations, the organizer, or
  destructive cleanup flows.
- For scripts that delete files, clear SQL data, or modify mounted storage, preserve or improve
  confirmations and safety checks.

## Git rules

- Read-only local Git inspection is allowed.
- Work directly on `main`; do not create feature branches. Commit and push completed scoped changes
  by default unless Oliver requests a separate branch or asks not to push.
- Rebases, resets, stashes, and destructive history changes require Oliver's explicit permission.

## Task-based reading map

Read the additional file that matches the work you are doing. If a task spans multiple areas, read all relevant files before acting.

- `agents/architecture.md` — read when touching Forge runtime, `work-state.json`, Docker or database
  workflows, storage switching, snapshots, tunnels, or database helper scripts.
- `agents/stations.md` — read when touching station metadata, SSH aliases, sleep/shutdown/boot flows, Wake-on-LAN, or network-topology-sensitive behavior.
- `agents/interfaces.md` — read when changing `dotfiles/aliases`, Linux alias parity, or any high-frequency user-facing command surface.
- `agents/preferences.md` — read when the task involves machine setup, tool installation, operator preferences, or Hades-specific environment choices.

## Editing rules

- Match the existing repo style and keep comments sparse.
- Prefer updating documentation when behavior or workflow meaning changes.
- When changing Angular guidelines under `.config/ai`, keep `angular-development.md` synchronized
  with the equivalent rule intent in the detailed Angular review set. Update both representations in
  the same change unless a rule is explicitly mode-specific; a mode-specific rule must explain why.
  Do not accept silent drift between development and review guidance.
- When a task depends on machine-specific paths, document assumptions instead of hardcoding new ones without reason.
