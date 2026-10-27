# Aldaris engine profiles (oMLX, TensorFold) — Aegis report

Date: 2026-10-27 · Station: Hades · Author: Aegis · No commits, branch or Git operations were made.

## Files changed or added

| File | Purpose |
| --- | --- |
| `scripts/aldaris-engines/omlx.sh` (new) | oMLX adapter: check, has_model, probe, start, loaded-check, safe stop |
| `configs/aldaris/catalog/engines/omlx.json` (new) | Engine entry (127.0.0.1:8000, key `aldaris-local`, idle 1800, monitor path `{storageRoot}/tools/omlx/`) |
| `configs/aldaris/catalog/models/qwen3.6-35b-a3b-8bit.json` | Added `engines.omlx` (`key` `mlx-community/Qwen3.6-35B-A3B-8bit`, `servedId` `Qwen3.6-35B-A3B-8bit`); `lmstudio` untouched |
| `configs/aldaris/profiles/scenario-2.json` (new) | oMLX + Qwen 8-bit, 131072 context, preset `qwen3.6-coding` |
| `.config/ai/README.md` | Profiles listed, `omlx` adapter behaviour, TensorFold wording corrected |
| `configs/alias-descriptions.tsv` | `aldaris-stop` now mentions oMLX |

`aldaris_config.py` needed no change (`external.json`, `ALDARIS_DEFAULT_PROFILE` unchanged).
Stale `tools/omlx/server.pid` and `tools/tensorfold/server.pid` were removed after confirming no process ran.

## oMLX settings (`/Volumes/dock-ssd/ai/tools/omlx/base/settings.json`, no secrets shown, mode 600)

- `scheduler.max_concurrent_requests` = 1
- `server.gpu_keep_warm_interval` = 0 (source: 0 or less disables keep-warm)
- `server.cors_origins` = `["http://localhost", "http://127.0.0.1"]`
- `auth.secret_key` not touched.
- Idle unload: oMLX has no flag; `engine_ensure_running` writes `idle_timeout.idle_timeout_seconds` = `$IDLE_SECONDS`
  (1800) into settings.json before each start. Verified in the file after the live run.
- Context: oMLX has no per-load context setting; the adapter writes `sampling.max_context_window_policy` =
  `$CONTEXT_LENGTH` (131072), a cap on the advertised/allowed window (oMLX otherwise reports 262144). It does not
  pre-allocate memory.
- The adapter also re-asserts concurrency 1 and keep-warm 0 on each start. A temporary settings backup was deleted.

## Verification

- `bash -n scripts/aldaris-engines/omlx.sh`: OK. `shellcheck`: not installed. No Python files changed.
- `aldaris_config.py list engines`: `external`, `lmstudio`, `omlx`.
- `list models --engine omlx`: `qwen3.6-35b-a3b-8bit … 37.75 GB mlx-community/Qwen3.6-35B-A3B-8bit`.
- `resolve --profile scenario-2`: engine/adapter `omlx`, model `Qwen3.6-35B-A3B-8bit`, 131072, 127.0.0.1:8000,
  monitor path `/Volumes/dock-ssd/ai/tools/omlx/` (key not reproduced here).
- `verify`: no output, exit 0 at time of run. `status`: `scenario-1`, `ok … (.model)`.

### Live switch (final run, after the fix below)

1. `apply scenario-2 --yes`: succeeded; LM Studio not running, oMLX not started (no process, port 8000/1234 closed).
2. Started through `aldaris_load_active` + `engine_ensure_running` + `engine_ensure_loaded`: ready.
   Chat completion with `max_tokens` 512: `finish_reason: stop`, answer `ok`. oMLX log line:
   `161 tokens in 2.15s (74.9 tok/s)`. (An earlier run logged `193 tokens in 2.30s (83.8 tok/s)`; the log figure
   includes prefill. The response's own `generation_tokens_per_second` was 103.3 in that run.)
3. `apply scenario-1 --yes`: oMLX gone (no process, port 8000 closed), PID file removed, no `~/.omlx`.
4. `aldaris-configure stop` (same command as the `aldaris-stop` alias): `Aldaris stopped; nothing resident.`
5. `status`: `scenario-1` active, `ok`.

The previous report's "~77 tok/s" was wrong; use the log numbers above. Its 14.5 tok/s run had only 64 tokens
including prefill and load.

### Bug found and fixed during the live test

First run: oMLX renames its process title to `omlx-server`, so the planned `ps -o command=` check for
`tools/omlx/venv` never matched. `engine_stop` removed the PID file without killing the server, and
`Aldaris stopped; nothing resident.` was still printed, because `aldaris-monitor.py --check-idle` matches on
command lines. I stopped the orphan by hand (PID verified via `lsof`), then changed `engine_stop` to identify the
process by its executable (`lsof -p <pid> -d txt` under `tools/omlx/`, which is the dock-ssd python) before
killing. It then passed the full run above.

## TensorFold

Not added to the catalog. Installed under `tools/tensorfold` but it cannot serve the existing 8-bit
Qwen3.6-35B-A3B checkpoint (native engine has no `qwen3_5_moe` backend; Python 0.6.6 reads only the 4-bit
`TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP` weights). No supported checkpoint was approved, so nothing was
downloaded. `scenario-3` is reserved. It would need: Oliver's approval to download a supported checkpoint (size
unchecked), a `tensorfold.sh` adapter built like `omlx.sh` (port 8002, process identity by executable), a model
JSON for that checkpoint, `engines/tensorfold.json`, `scenario-3`, and its own Python under
`tools/tensorfold/` (`venv-py066` currently reuses `tools/omlx/python312`).

## Decisions / open items for Oliver

1. `aldaris-monitor.py --check-idle` (and the fallback stop in `aldaris_config.py stop-processes`) match command
   lines, so they cannot see an oMLX process that renamed itself. The adapter now covers the normal path, but a
   crashed adapter or lost PID file would leave an orphan that `aldaris-stop` reports as "nothing resident".
   I did not change the monitor (out of scope); suggest a listening-port or open-file check for catalog paths.
2. TensorFold: approve a supported checkpoint download, or drop it.
3. Nothing was placed on the internal SSD; free space stayed at 406 GiB.

---

# Addendum: TensorFold added as `scenario-3` (Oliver approved the download)

Everything stayed on dock-ssd; internal SSD free space 407 GiB. Nothing is running afterwards.
The TensorFold section above ("Not added") is superseded by this addendum.

- **Checkpoint:** `TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP`, revision `81169a9bc511a27c1b4eedb77a2cd98ced431847`,
  downloaded with `hf download --local-dir` to `/Volumes/dock-ssd/ai/models/TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP` (19 GB).
- **Engine:** Python engine `tensorfold 0.6.6` (native Metal 1.1.6 still lacks `qwen3_5_moe`; the upstream recipe names the
  Python engine for Macs). It now has its own Python (`tools/tensorfold/python312`) and `venv`; `venv-py066` was removed.
  `tools/tensorfold` is 539 MB (the unused native 1.1.6 binary remains there).
- **Start (as the adapter does):** from `tools/tensorfold`, with `HF_HOME`, `XDG_CACHE_HOME`, `TMPDIR` under `cache/`, `HF_HUB_OFFLINE=1`:
  `venv/bin/python -m tensorfold serve <storageRoot>/models/TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP --host 127.0.0.1 --port 8002 --name Qwen3.6-35B-A3B-MLX-4bit-MTP --context 131072 --api-key aldaris-local --parallel 1 --max-tokens 8192 --no-update-check`.
  Stop: adapter `engine_stop` (PID file `tools/tensorfold/server.pid`; killed only if its executable is under `tools/tensorfold/`).
- **Served ID:** `Qwen3.6-35B-A3B-MLX-4bit-MTP`; `/v1/models` without the key returns 401.
- **Files added/changed:** `scripts/aldaris-engines/tensorfold.sh`, `catalog/engines/tensorfold.json`,
  `catalog/models/qwen3.6-35b-a3b-4bit-mtp.json` (new model, engine `tensorfold` only), `profiles/scenario-3.json`, README.
- **Live switch:** `apply scenario-3` → adapter start → READY → chat (`max_tokens` 512) `finish_reason: stop`, server log
  `tok/s=183.7` (an earlier manual run without a key: 149.4) → `apply scenario-1`: no process, ports 8000/8002/1234 closed,
  no PID files → `stop`: `Aldaris stopped; nothing resident.` → `status`: `scenario-1`, ok. `verify` exits 0.
- **Open points for Oliver:**
  1. The 0.6.6 engine has no idle-unload flag, so the model stays resident (19 GiB weights plus a prompt cache the engine
     sizes from free memory, ~59 GiB reported at 128K) until a switch or `aldaris-stop`. `--prompt-cache-gib` could cap it.
  2. This is a different model (4-bit, MTP) than scenario-1/2, so quality is not comparable; the 8-bit checkpoint is still unsupported.
  3. The monitor still cannot see renamed processes (open item 1); both adapters identify by executable.
