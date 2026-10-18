# Shared AI Instructions

This directory is the Git-tracked source of truth for shared Artanis, Argus, and Aegis
instructions.

On Unix stations, expose it through the conventional path:

```sh
ln -s "$HOME/mac-forge/.config/ai" "$HOME/.config/ai"
```

Do not replace complete tool-owned configuration directories such as `~/.codex`, `~/.claude`, or
`~/.copilot`. They contain local state. Their global instruction bootstrap files should load the
generated canonical base instruction set from `~/.config/ai`.

Start a new agent session after pulling instruction changes so the updated
global instruction chain is loaded.

## Context resolution

`ai-config install` generates each tool's global bootstrap from its tracked template and canonical
shared sources. Codex, Claude, and Copilot embed the small, stable base set so it is available at
session start. On MasterChief the installer manages Codex, Claude, and Copilot bootstraps and the
Work, Raynor, and Zeratul review-handoff lanes. Hades retains its single-universe project-lane
layout.

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

## Aldaris delegation

`junior-check` runs a read-only one-second process monitor (`scripts/junior-check.sh`). It identifies
LM Studio's inference worker, supporting processes, Qwen CLI, and their descendants dynamically.
CPU is measured from process CPU-time deltas (100% is one core); RSS is shown per process and summed
with a shared-memory caveat. GPU device utilization from IORegistry, memory pressure, and swap are
whole-Mac readings. It cannot attribute GPU utilization to an individual model/session. It neither
starts the model nor changes delegation state and needs no sudo. `--samples 2` gives a bounded
snapshot; `--interval 2` changes the refresh interval; Ctrl+C restores the terminal and exits.

Control assistant delegation with `junior on`, `junior off`, and `junior status` (or
`scripts/aldaris-junior.sh`). The default is OFF; the non-secret switch is stored in the ignored
`config-local/aldaris-junior.state`, separate from shared configuration and the external drive.
Assistants check it at task start and before each dispatch. ON requires actively seeking useful
eligible subtasks and announcing every invocation and outcome. OFF means solo work and blocks the
text helper before inference; results arriving after OFF are discarded. It does not close Oliver's
manual `aldaris` sessions or unload their model. An already submitted inference may finish.

The current automatic ceiling remains `trivial`. This switch does not grant automatic coding-edit
permissions: isolated coding jobs and capability approval remain separate from the manual launcher.

Aldaris uses Qwen3.6-35B-A3B at 8-bit precision through LM Studio's MLX runtime on Hades.
Run `aldaris` from a repository to start a supervised Qwen Code coding session. The launcher
starts the localhost server and loads the model as needed, uses 128K context and a 30-minute idle
unload timeout, and refuses to start without `dock-ssd` mounted. Repository instructions and
Oliver's explicit approval requirement for unit tests still apply. The model, standalone Qwen Code installation, Qwen session data, helper logs, and caches live under
`/Volumes/dock-ssd/ai`. LM Studio and its small discovery/support files remain on the internal SSD for reliable runtime
discovery. Its model library points directly to the external drive, and its large runtime dependency
directory is linked from `~/.lmstudio/extensions/backends/vendor` to
`/Volumes/dock-ssd/ai/lmstudio/runtime/vendor`. Qwen settings are recorded in
`configs/aldaris/qwen-settings.json` and installed at `/Volumes/dock-ssd/ai/qwen/settings.json`.

`scripts/aldaris-ask.sh` remains a bounded text-only delegation interface with templates, schemas,
caller/level checks, and visible logging. Start `aldaris` first to load the model. Its current
`maxLevel` remains `trivial`; only Oliver changes it. The shared delegation rules apply to that
interface, while interactive coding sessions are separately supervised. No coding-quality acceptance
is implied by installation. Settings live in `configs/aldaris/config.json` and the coding-session
instructions in `configs/aldaris/instructions.md`. The text adapter handles LM Studio MLX routing
schema-constrained JSON into `reasoning_content`, accepting it only when it parses as JSON.

## Review handoff roles

Default roles: Artanis prepares a review as Coworker and Argus reviews. When Oliver explicitly
asks (for example "Aegis, hand off to Artanis for review"), any of the three identities may be the
Coworker or the Reviewer for that one handoff; both names are recorded in the request and findings
headers. Lane structure is unchanged: MasterChief keeps `work`, `raynor`, and `zeratul`; Hades keeps a
single universe with one project lane per repository. `bin/review-handoff-verify.sh` validates the
MasterChief lanes, including distinct Coworker and Reviewer identities.

The manual handoff remains the default and returns to Oliver after every review and findings-analysis
step. `scripts/team-work.sh --prompt <task>` is a separate opt-in flow: it launches and resumes the
two real assigned CLI sessions and advances only structured transporter states. When ambiguity,
sustained blocking disagreement, scope expansion, an integrity violation, or the cycle limit needs
Oliver's decision, the running coordinator waits in the same terminal; enter the decision directly
and it resumes the recorded sessions. Reviewer approval ends the loop and returns the result to
Oliver. Enter `/stop` at a decision prompt to end without approval; the next invocation may start a
new task. The coordinator never reviews code or simulates a team identity.

Each autonomous task writes an owner-only Markdown transcript under the active handoff lane's
`transcripts/` directory. Its filename combines a short slug derived from the task prompt with a UTC
timestamp. The transcript records Oliver's prompt and decisions, participant prompts and final
responses, request/findings snapshots, verdicts, pauses, and the outcome. It is an audit and recap
artifact, not a source of loop control, hidden reasoning, or raw tool events.

The workflow refuses to start over substantive pending repository changes. Git-ignored paths, known
local license artifacts, and `local-overrides/` do not block it. A repository may declare another
routine local-only path or glob without changing tracked files:

```sh
git config --local --add team-work.allowedDirtyPath 'path/or/glob'
```

This exception is a baseline allowance, not permission for either participant to modify that path.

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
