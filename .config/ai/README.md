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

The embedded set is loaded into every request, so keep it concise without dropping rules. Every
prohibition and every always-applicable duty stays embedded. Only procedural detail may move to an
on-demand file, and the embedded set must name it with a mandatory trigger: currently only
`guidelines/rule-lifecycle.md`, read for any provisional-rule proposal or change. Do not place
on-demand files directly under `guidelines/always/`; every file there is embedded.

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

## Aldaris

Aldaris remains a team member for bounded tasks that Oliver alone starts and manages on demand,
where he reads the shared guidelines. By Oliver's decision (2026-10-22), Artanis, Argus, and Aegis do
not delegate work to Aldaris or otherwise interact with him, except through review handoffs in which
Aldaris is the Coworker: his output quality is insufficient for assistant delegation. The former
assistant delegation tooling (`aldaris-ask`, its templates and schemas, and the `junior` switch) was
removed with that decision.

`junior-check` shows a compact three-row GPU/MEM/CPU matrix with Total and Junior columns,
refreshing every second (`scripts/junior-check.sh`). Junior includes LM Studio, Qwen CLI and their
descendants. CPU percentages use whole-Mac capacity (100% is all logical cores). Total memory uses
the same anonymous/wired/compressed-page calculation as `inf`; Junior memory is the process RSS sum,
which can count shared pages more than once. GPU utilization is whole-Mac IORegistry telemetry;
Junior GPU shows NSM (not separately measurable) because it cannot be attributed to individual processes.
The monitor does not start the model and needs no sudo. `--samples 2` gives a bounded snapshot;
`--interval 2` changes the refresh interval; Ctrl+C exits.

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

No coding-quality acceptance is implied by installation. Settings live in
`configs/aldaris/config.json` and the coding-session instructions in
`configs/aldaris/instructions.md`.

## Review handoff roles

Default roles: Artanis prepares a review as Coworker and Argus reviews. When Oliver explicitly
asks (for example "Aegis, hand off to Artanis for review"), any of the three identities may be the
Coworker or the Reviewer for that one handoff; both names are recorded in the request and findings
headers. On Hades, Aldaris may also be the Coworker of a manual handoff (reviewed by Argus unless
Oliver names Artanis or Aegis); he never reviews and does not take part in autonomous team loops. Lane structure is unchanged: MasterChief keeps `work`, `raynor`, and `zeratul`; Hades keeps a
single universe with one project lane per repository. `bin/review-handoff-verify.sh` validates the
MasterChief lanes, including distinct Coworker and Reviewer identities.

## QA handoff

QA is the last step of a task, enabled on Hades only for now. After the code-review cycle ends with
Coworker, Reviewer, and Oliver in agreement, and Oliver has deployed the app on a disposable VPS1
snapshot database and given its URL and an optional depth (`surface`, `medium` by default, or
`verbose`), the Coworker decides what to test from the task and writes a self-sufficient request: URL,
login, pages, steps, and expected results. The Tester uses the running app like a user and reports.
Oliver reads the report first, then asks the Coworker, the code reviewer, or both to process it. The word `QA` in Oliver's command
selects this kind: "Prep for Artanis QA takeoff" / "QA handoff to Aegis" (Coworker), "Artanis QA
takeoff" / "Process Argus's QA handoff" (Tester), and "Process Aegis's QA report" (Coworker or code reviewer).
Commands without `QA` keep their code-review meaning.

Artanis tests by default; any of the three may test when its session has a working browser tool. The
pair is `qa-request-<coworker>.md` and `qa-report-<coworker>.md`, with captures in
`qa-evidence-<coworker>/`. The Tester may perform any operation on the given URL, data changes
included; it stops and asks Oliver when the app is not functional there or a snapshot restore is
needed. Agents never build, start, deploy, or restore anything for QA. QA never runs through
`team-work.sh`, and it does not authorize automated test suites.

The resolver keeps routing cheap: `--mode handoff` loads `handoff/common.md`, `handoff/review.md`, and
the station flow; `--mode qa-handoff` loads `handoff/common.md`, `handoff/qa.md`, and the station flow.
Only the short kind table in `always/review-handoff.md` is always loaded.

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
