# Aldaris engine profiles (oMLX, TensorFold) — next step for Aegis

Date recorded: 2026-10-27  
Station: Hades  
Written by: Argus, at Oliver's request  
Assigned to: Aegis  
Repository: `/Users/oliver/mac-forge`  
Previous step: `aldaris-alternative-engines-aegis-step.md` and its report (reviewed by Argus; see
"Review findings to apply" below)

## Goal

Keep the current default flow unchanged: profile `scenario-1`, LM Studio with Qwen3.6-35B-A3B
8-bit. Next to it, add saved configurations to switch to:

- **oMLX** (installed and verified): add it now as profile `scenario-2`.
- **TensorFold**: only if it is installed **and** can serve a model. Today it cannot serve the
  existing 8-bit checkpoint, and downloading a TensorFold-supported checkpoint needs Oliver's
  approval first. Unless Oliver has approved and the server actually serves a model, do **not**
  add TensorFold to the catalog. Record its status in the report instead.

Switching uses the existing tools: `aldaris-configure apply scenario-2` or the fzf picker, and
`aldaris-configure apply scenario-1` to go back.

## Read first

- `AGENTS.md`, then `agents/architecture.md` and `agents/interfaces.md` (repo rules)
- `.config/ai/README.md`, Aldaris section (catalog, adapters, resource policy)
- `scripts/aldaris-lib.sh`, `scripts/aldaris-configure.sh`, `scripts/aldaris.sh`
- `scripts/aldaris-engines/lmstudio.sh` (adapter contract in its header) and `external.sh`
- `scripts/agents/aldaris_config.py`, in particular `resolve()` and `cmd_stop_processes`
- `configs/aldaris/catalog/**` and `configs/aldaris/profiles/scenario-1.json`
- `brainstorm/2026-10-27/aldaris-alternative-engines-aegis-report.md` (your oMLX start/stop data)

The Aldaris configurability work is **uncommitted** on branch `refactor-optimize-ai-work`. Build on
the working tree as it is. Do not commit, stash, reset, rebase or switch branches.

## Work

### 1. oMLX adapter: `scripts/aldaris-engines/omlx.sh`

Implement the same contract as `lmstudio.sh`: `engine_check`, `engine_has_model`,
`engine_probe`, `engine_ensure_running`, `engine_ensure_loaded`, `engine_stop`. Use a dedicated
adapter, not `external`: the resource policy requires Aldaris to start and stop oMLX itself.

- `engine_has_model` and `engine_stop` run **without** an active selection (`aldaris-configure`
  sources the adapter directly), so they must not depend on globals from `aldaris_load_active`.
  Derive the storage root from `$FORGE_ROOT/configs/aldaris/catalog/global.json` (`storageRoot`)
  rather than hardcoding `/Volumes/dock-ssd/ai`.
- `engine_check`: `tools/omlx/venv/bin/omlx` exists and is executable.
- `engine_has_model <key>`: return 0 if `tools/omlx/models/<key>` exists (the symlink to the LM
  Studio weights) and 1 otherwise. The model key is `mlx-community/Qwen3.6-35B-A3B-8bit`.
- `engine_ensure_running`: if `$BASE_URL/models` (with the bearer key) does not answer, start
  `omlx serve` with the flags from your report. Set `PIP_CACHE_DIR`, `XDG_CACHE_HOME`, `TMPDIR`
  and `HF_HOME` under `cache/`, bind to `$HOST`/`$PORT`, pass `--api-key "$API_KEY"`, and log to
  `tools/omlx/server.log`. Write the PID file, then wait (bounded, e.g. 60 s) until `/models`
  answers. On timeout, print the log path and return 1.
- `engine_ensure_loaded`: confirm `/models` lists `$MODEL` (oMLX loads on first request). If oMLX
  supports a context-length or idle-unload setting, apply `$CONTEXT_LENGTH` and `$IDLE_SECONDS`
  through it; if not, say so in the report.
- `engine_stop` (graceful, safe):
  - Read `tools/omlx/server.pid`. Kill the process only if `ps -p <pid> -o command=` shows it
    runs from `tools/omlx/venv`. Then remove the PID file.
  - Remove the `~/.omlx` directory oMLX creates on start (it only contains the
    `bin/omlx-cluster-python` symlink; verify before removing).
  - Return 0 when nothing is running.

### 2. Catalog and profile

- `configs/aldaris/catalog/engines/omlx.json`: `adapter: "omlx"`, host `127.0.0.1`, port `8000`,
  `formats: ["mlx"]`, `apiKey: "aldaris-local"` (local placeholder, same status as `lm-studio`),
  `idleSeconds: 1800`, `monitorProcessPatterns: ["{storageRoot}/tools/omlx/"]`.
- In `configs/aldaris/catalog/models/qwen3.6-35b-a3b-8bit.json`, add
  `"omlx": { "key": "mlx-community/Qwen3.6-35B-A3B-8bit", "servedId": "Qwen3.6-35B-A3B-8bit" }`
  under `engines`. Leave the `lmstudio` entry as it is.
- `configs/aldaris/profiles/scenario-2.json`: engine `omlx`, the same model, context `131072`,
  preset `qwen3.6-coding`, description `oMLX + Qwen3.6-35B-A3B 8-bit, 128K context`.
- Keep `ALDARIS_DEFAULT_PROFILE="scenario-1"` and `external.json` unchanged.
- If `aldaris_config.py` validation rejects the new engine (it only requires a model `key` for
  `lmstudio`), make the smallest change that fixes it and explain it in the report.

### 3. oMLX server settings (on dock-ssd, outside the repo)

In `/Volumes/dock-ssd/ai/tools/omlx/base/settings.json`, or through the matching CLI flags if oMLX
offers them:

- set `max_concurrent_requests` to 1
- stop GPU keep-warm while idle (`gpu_keep_warm_interval`; find the supported way to disable it)
- set `cors_origins` to localhost only

Edit with `jq` or Python **without printing the file**: it contains `auth.api_key` and
`auth.secret_key`. Never show either value in a terminal, log or report. Do not rotate the
`secret_key`; that is Oliver's decision.

### 4. TensorFold (conditional)

Unless Oliver has approved a supported checkpoint **and** `tensorfold serve` answers
`/v1/models` with a working chat completion, change nothing for TensorFold. In that case, write in
the report that `scenario-3` is reserved for it and what it would need (adapter
`tensorfold.sh` built the same way as oMLX's, port `8002`, a model JSON for the supported
checkpoint).

If it does qualify, add it the same way: adapter, `engines/tensorfold.json` (port 8002), the
model's `engines.tensorfold` entry, and profile `scenario-3`. It must also get its own Python
under `tools/tensorfold/`, because `venv-py066` currently reuses `tools/omlx/python312`.

### 5. Documentation

- `.config/ai/README.md`, Aldaris section: list the profiles (`scenario-1` default LM Studio,
  `scenario-2` oMLX), describe the `omlx` adapter's start/stop behaviour, and remove TensorFold
  wording that implies it works today.
- `configs/alias-descriptions.tsv`: update `aldaris-stop` so it doesn't say only "LM Studio".

## Verification

Allowed: `bash -n` on every changed shell file, `shellcheck -x` if installed,
`/usr/bin/python3 -m py_compile` on changed Python files, and read-only `aldaris_config.py`
queries (`list engines`, `list models --engine omlx`, `resolve --profile scenario-2`, `verify`,
`status`).

Live switch (oMLX loads a ~35 GB model; one engine at a time):

1. `aldaris-configure apply scenario-2 --yes`: LM Studio must be stopped, oMLX not yet started.
2. Source `scripts/aldaris-lib.sh`, run `aldaris_load_active`, then `engine_ensure_running` and
   `engine_ensure_loaded`. Send one chat completion with curl to `$BASE_URL/chat/completions`
   using `max_tokens` ≥ 512 (Qwen3.6 spends the first tokens on reasoning). Record the measured
   tokens/s from the oMLX log line, not an estimate.
3. `aldaris-configure apply scenario-1 --yes`: oMLX must be fully stopped and its PID file gone.
4. `aldaris-stop`: it must print `Aldaris stopped; nothing resident.`
5. Finish with `aldaris-configure status` showing `scenario-1` active and `ok`.

Do **not** run `aldaris`: that launches Aldaris, which only Oliver starts. Don't run unit tests.

## Boundaries

- No commits or branch operations (see "Read first").
- Don't modify LM Studio, its model library, or the model weights. Download nothing without
  Oliver's approval.
- Keep everything that can live on dock-ssd under `/Volumes/dock-ssd/ai`. Ask before putting
  anything on the internal SSD.
- Don't involve, launch or contact Aldaris.

## Review findings to apply from the previous step

- Your previous report's "~77 tok/s" did not match the oMLX log (`14.5 tok/s`, 64 tokens). Report
  only measured numbers.
- Stale `server.pid` files remain in `tools/omlx` and `tools/tensorfold`. Remove them after
  confirming no matching process runs. Stop logic must never kill a reused PID.

## Report back

Write `brainstorm/2026-10-27/aldaris-omlx-tensorfold-profiles-aegis-report.md` with:

- the list of files changed or added, each with a one-line purpose
- oMLX settings changed (names and new values, no secrets) and how idle unload and context are
  handled
- the output of each verification command, plus the live-switch results (steps 1–5) and measured
  tokens/s
- TensorFold status and what it would need
- anything you could not do, and any decision that is Oliver's
