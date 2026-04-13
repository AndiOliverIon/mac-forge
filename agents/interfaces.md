# Interfaces scope

Read this file when changing aliases, high-frequency scripts, or other user-facing command surfaces.

## Public interface guidance

- Aliases in `dotfiles/aliases` are part of the public interface of this repo.
- Treat aliases and high-frequency scripts as stable operator-facing entry points.
- Preserve backward-compatible names where practical when refining behavior.

## Alias parity

- When changing a user-facing alias in `dotfiles/aliases`, update the corresponding Linux alias file too when that command surface exists there.
- Keep naming consistent across macOS and Linux surfaces unless there is a platform-specific reason not to.

## Documentation guidance

- If an interface change alters behavior meaning, update documentation to reflect the new contract.
- Prefer explicit naming over clever naming for operational commands, especially destructive or stateful ones.
