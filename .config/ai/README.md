# Shared AI Instructions

This directory is the Git-tracked source of truth for shared Artanis, Karax, Argus, Aegis, and
Talandar instructions.

On Unix stations, expose it through the conventional path:

```sh
ln -s "$HOME/mac-forge/.config/ai" "$HOME/.config/ai"
```

Do not replace complete tool-owned configuration directories such as `~/.codex`, `~/.grok`,
`~/.claude`, or `~/.config/opencode`. They contain local state. Their global instruction bootstrap
files should load the generated canonical base instruction set from `~/.config/ai`.

Start a new agent session after pulling instruction changes so the updated
global instruction chain is loaded.

## Context resolution

`ai-config install` generates each tool's global bootstrap from its tracked template and canonical
shared sources. Codex, Claude, Copilot, and OpenCode embed the small, stable base set so it is
available at session start. Grok's 10,000-character project-rules limit requires a compact native
`~/.grok/AGENTS.md`; Karax uses it to load the canonical base sources through the resolver before
task work. The installer also sets `[compat.claude] agents = false` in Grok's user configuration so
Grok does not import Argus's global Claude identity; Claude-compatible skills, rules, and MCP
settings remain available. On MasterChief the installer manages Codex, Grok, Claude, and Copilot
bootstraps and the Work, Raynor, and Zeratul review-handoff lanes. On Hades it also manages
OpenCode's `~/.config/opencode/AGENTS.md` bootstrap for Talandar while preserving OpenCode's model
and provider configuration. Hades retains its single-universe project-lane layout.

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

## Review handoff roles

Default roles: Artanis or Karax prepares a review as Coworker and Argus reviews. When Oliver explicitly
asks (for example "Aegis, hand off to Karax for review"), any of the four identities may be the
Coworker or the Reviewer for that one handoff; both names are recorded in the request and findings
headers. Lane structure is unchanged: MasterChief keeps `work`, `raynor`, and `zeratul`; Hades keeps a
single universe with one project lane per repository. `bin/review-handoff-verify.sh` validates the
MasterChief lanes, including distinct Coworker and Reviewer identities. Talandar remains outside
this formal rotation unless Oliver explicitly promotes or assigns him to a handoff role.

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
  generated station-appropriate bootstrap files, station routing, all MasterChief handoff lanes,
  active MasterChief agent context, and local Mac Forge Git state.
- `install` backs up conflicting config or bootstrap paths before replacement.
  It never replaces a complete tool-owned configuration directory.
- `sync` refuses a dirty Mac Forge checkout, pulls with `--ff-only`, runs
  verification, and reminds the operator to start fresh agent sessions.
