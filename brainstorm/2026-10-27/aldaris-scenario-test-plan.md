# Aldaris scenario comparison — test plan

Date recorded: 2026-10-27  
Station: Hades  
Written by: Argus, for Oliver  
Run by: Oliver (only Oliver launches Aldaris)  
Reviewed by: Argus, from the saved results

## Goal

Decide which engine/model setup Aldaris should use day to day, by giving every scenario the same
tasks and comparing quality, reliability and speed.

| Profile | Engine | Weights | Answers |
| --- | --- | --- | --- |
| `scenario-1` (default) | LM Studio | 8-bit | baseline |
| `scenario-2` | oMLX | 8-bit (same files) | engine effect at 8-bit (vs 1) |
| `scenario-3` | TensorFold | 4-bit + MTP | engine effect at 4-bit (vs 4) |
| `scenario-4` | oMLX | 4-bit + MTP (same files as 3) | 8-bit vs 4-bit on one engine (vs 2) |

All four use 128K context, the `qwen3.6-coding` preset (temperature 0.6, top_p 0.95, top_k 20,
8K output) and thinking on.

## Setup (already done)

- Evaluation copy: `/Volumes/dock-ssd/ai/aldaris-eval/mac-forge`. It is a clone of mac-forge at
  `9e4d4ec` plus one local commit `a7fbf3f Evaluation fixtures` (the `eval/` folder). It has no Git
  remote and no `config-local/`, so Aldaris cannot push or read secrets from it.
- `/Volumes/dock-ssd/ai/aldaris-eval/reset.sh` resets the copy to `a7fbf3f` and refuses to touch
  any other repository.
- `/Volumes/dock-ssd/ai/aldaris-eval/save.sh <scenario-N> <T1..T7> <run> ["notes"]` saves the run's
  diff, status, commits, notes and the engine log tail to `aldaris-eval/results/`, then resets.

## Procedure per scenario

1. `aldaris-stop`. It must print `Aldaris stopped; nothing resident.`
2. `aldaris-configure apply scenario-N`
3. `cd /Volumes/dock-ssd/ai/aldaris-eval/mac-forge && /Volumes/dock-ssd/ai/aldaris-eval/reset.sh`
4. **Warm-up (not scored):** start `aldaris`, ask `Reply with the word ready.`, then
   `List the files in eval/.` Watch three things:
   - the model loads (for `scenario-4` this is the first real proof that oMLX can load the 4-bit
     checkpoint);
   - reasoning is shown separately from the answer;
   - the file-listing tool call works.

   Quit. If the warm-up fails, note it and skip that scenario.
5. For each task T1–T7: start a **fresh** `aldaris` session in the copy, paste the prompt below word
   for word, and supervise as usual. Don't hint beyond answering a direct question. Then quit and
   run `save.sh scenario-N T# 1 "notes"`.
6. In the notes, record: solved yes/no in your view, your interventions (count), tool-call errors
   (count), approximate wall time, peak RAM from `junior-check` if you watched it, and anything
   surprising.

Order: `scenario-1` → 2 → 3 → 4. Phase 1 is one run per task (28 sessions, roughly 3–4 hours in
total; it can be spread over days because every run starts from the same reset). Phase 2: repeat
only the tasks where two scenarios came out close, as run 2. Temperature 0.6 makes single runs
noisy.

Safety while supervising:
- T5 says "do not run it". **Deny** any request to execute `eval/cleanup-cache.sh`. Deny any
  command that would touch something outside the evaluation copy.
- Deny running unit tests or db/deploy scripts. None of the tasks needs them.

## Tasks (paste exactly)

**T1 — explain (read-only, real code)**
> Explain how `scripts/agents/aldaris-monitor.py` decides which processes belong to Aldaris, and
> where it gets the storage root from. Do not change any files.

**T2 — bash bug fix**
> `eval/rotate-logs.sh` is supposed to keep the newest KEEP `.log` files in a directory and delete
> the rest, but it is buggy. Fix it. Keep the same usage. Change no other files.

**T3 — Python fix to a specification**
> Make `parse_size` in `eval/parse_size.py` behave exactly as its docstring specifies. Do not add
> test files. Change no other files.

**T4 — multi-file feature**
> In `eval/inventory/`, give every station a `role`: alpha is `dev`, bravo is `build`, charlie is
> `db`. Show it as a ROLE column in `report.sh`, add a `--role <name>` filter that can be combined
> with `--os`, and update the README.

**T5 — review (no edits)**
> Review `eval/cleanup-cache.sh` for correctness and safety. List your findings by severity, each
> with the line and a suggested fix. Do not edit or run it.

**T6 — repo-instruction following**
> Add an alias `eval-hello` that runs `eval/hello.sh`, following this repository's rules for
> aliases.

**T7 — search across the repository**
> Which scripts under `scripts/` can delete Docker volumes? For each, give file:line and say
> whether a confirmation protects it. Do not change any files.

---

## Expected outcomes (for Argus's review — do not paste into Aldaris)

**T1.** It runs `ps -axo pid=,ppid=,time=,rss=,comm=`. Matching rules:
- `<storageRoot>/tools/qwen-code/` → Qwen CLI;
- `/LM Studio.app/` → LM Studio UI or helper;
- `/.lmstudio/` or `<storageRoot>/lmstudio/` → LM Studio service, or INFERENCE worker when the
  command line contains `llmworker.js`.

Children of selected processes are added repeatedly until none are left; its own PID is excluded.
The storage root comes from `storageRoot` in `configs/aldaris/config.json` (in this copy).
`junior-check.sh` is a wrapper for it. Deduct points for invented rules or for describing the
uncommitted catalog version.

**T2.** Bugs it must fix:
- off-by-one: `-ge` keeps only KEEP−1 files, it should be `-gt`;
- word splitting: unquoted `$DIR`, and `for f in $files` over `ls` output, break on spaces;
- with no matching `.log` files, `ls` fails under `set -e`; that case should be a quiet no-op.

Good extras: a usage check for a missing `<dir>`, numeric validation of KEEP, iterating a glob
array or using `find`/`stat` instead of parsing `ls`. Deduct for changed usage or files changed
outside `eval/rotate-logs.sh`.

**T3.** Required:
- binary units (1024, not 1000);
- case-insensitive, with an optional space and optional trailing `B` (`"2 mb"`, `"1KB"`);
- `ValueError` (not `IndexError`) for `""`, plus `"abc"`, `"-1K"` and `"1X"`;
- `"512"` gives 512 and `"1.5G"` gives 1610612736.

Deduct for an added test file or for changing the documented examples.

**T4.** Required:
- all three files changed (`stations.json` roles exactly as given, `report.sh`, `README.md`);
- ROLE column aligned with the header;
- `--role` validated like `--os` (`${2:?…}`), and both filters combined with AND in the jq select;
- the usage comment in `report.sh` updated.

Deduct for breaking `--os` or the table layout.

**T5.** Expected findings:
- *Critical:* an empty or missing project (no `set -u`) makes it `rm -rf ~/.cache/builds/*`, i.e.
  it wipes every project's cache.
- *Critical:* path traversal, e.g. `../..` deletes outside the cache root.
- *High:* no confirmation, against this repo's rules for deletion scripts.
- *Medium:* no `set -euo pipefail` or argument check.
- *Medium:* it prints "Cleared" even when nothing existed or `rm` failed.
- *Low:* the glob skips dotfiles.

It must not edit or run the script; running it is a serious instruction failure.

**T6.** `AGENTS.md` points to `agents/interfaces.md` for alias work. A complete answer:
- adds `alias eval-hello="~/mac-forge/eval/hello.sh"` to `dotfiles/aliases`;
- adds an `eval-hello` row to `configs/alias-descriptions.tsv` (used by `help.sh` and `aliases.sh`);
- considers Linux parity (`linux/aliases.zsh`): adding it there, or saying it isn't needed there
  with a reason, are both acceptable.

Deduct for editing only `dotfiles/aliases`, or for not reading the alias guidance.

**T7.** Exactly one: `scripts/docker-clean-known-facts.sh:134` (`docker volume rm "$volume"`),
protected by the confirmation prompt at line 117, which `-y`/`--yes` skips. `db-restore.sh` and
`db-restore-files.sh` only inspect or create volumes. Listing them as deleting is a false positive.

## Score sheet (Argus fills it from `results/`)

Per run, 0–3 each: correctness, instruction following, change discipline (only the requested
files), and tool-use reliability. Also: interventions, wall time, tok/s from the engine log, and
peak RAM.

| Task | S1 | S2 | S3 | S4 | Notes |
| --- | --- | --- | --- | --- | --- |
| T1 | | | | | |
| T2 | | | | | |
| T3 | | | | | |
| T4 | | | | | |
| T5 | | | | | |
| T6 | | | | | |
| T7 | | | | | |
| Total / speed / RAM | | | | | |

When a phase is done, say "Check the Aldaris evaluation results" and Argus scores every saved run
against the expected outcomes and gives a verdict.
