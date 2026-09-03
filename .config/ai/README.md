# Shared AI Instructions

This directory is the Git-tracked source of truth for shared Artanis, Argus,
and Aegis instructions.

On Unix stations, expose it through the conventional path:

```sh
ln -s "$HOME/mac-forge/.config/ai" "$HOME/.config/ai"
```

Do not replace the complete `~/.codex` or `~/.claude` directories. They contain
tool-owned local state. Their global instruction bootstrap files should load
the generated canonical base instruction set from `~/.config/ai`.

Start a new agent session after pulling instruction changes so the updated
global instruction chain is loaded.

## Context resolution

`ai-config install` generates each tool's global bootstrap from its tracked template plus the
canonical identity, router, and direct always-applicable sources. This makes the small, stable base
set available at session start without duplicating its rules in tracked files or reading it through
a latency-sensitive tool call.

The global bootstrap invokes `bin/ai-context.sh` before task work. The resolver combines the
canonical `configs/stations.json` inventory with the current hostname, scope path, Git metadata, and
review corpus. It reports the station, execution universe, canonical repository, mode, represented
stacks, and ordered stack, project, and provisional instruction paths to load next. It also packs
those paths, without reordering or omission, into deterministic 22 KiB batches. Run each emitted
batch command in numeric order. The batch reader verifies file counts and byte totals, wraps every
source in boundary markers, and emits a final completion marker so truncation is detectable.
`NEXT_INSTRUCTION_PATHS` remains the file-by-file fallback. The output is ephemeral; no
current-context file is written.

Use `ai-context --help` for its scope arguments. A partial result is expected when the repository or
target files are not yet known; identify only the missing scope and rerun it.

## Management

Use the cross-platform helper from either Hades or MasterChief:

```sh
ai-config verify
ai-config install
ai-config sync
```

The shell aliases provide `ai-verify` for `ai-config verify` and `ai-install`
for `ai-config install`. Reload the shell after pulling an alias change.

- `verify` is read-only. It checks every required shared instruction source, the shared symlink,
  generated Codex and Claude bootstrap files, station routing, active MasterChief agent context, and
  local Mac Forge Git state.
- `install` backs up conflicting config or bootstrap paths before replacement.
  It never replaces the complete `~/.codex` or `~/.claude` directory.
- `sync` refuses a dirty Mac Forge checkout, pulls with `--ff-only`, runs
  verification, and reminds the operator to start fresh agent sessions.
