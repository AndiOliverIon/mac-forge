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
