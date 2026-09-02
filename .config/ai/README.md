# Shared AI Instructions

This directory is the Git-tracked source of truth for shared Artanis, Argus,
and Aegis instructions.

On Unix stations, expose it through the conventional path:

```sh
ln -s "$HOME/mac-forge/.config/ai" "$HOME/.config/ai"
```

Do not replace the complete `~/.codex` or `~/.claude` directories. They contain
tool-owned local state. Their global instruction bootstrap files should load
`~/.config/ai/identities.md` and `~/.config/ai/guidelines/guidelines.md`.

Start a new agent session after pulling instruction changes so the updated
global instruction chain is loaded.

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
  canonical Codex and Claude bootstrap files, station routing, active MasterChief agent context, and
  local Mac Forge Git state.
- `install` backs up conflicting config or bootstrap paths before replacement.
  It never replaces the complete `~/.codex` or `~/.claude` directory.
- `sync` refuses a dirty Mac Forge checkout, pulls with `--ff-only`, runs
  verification, and reminds the operator to start fresh agent sessions.
