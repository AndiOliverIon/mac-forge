# Aldaris alternative engines — next step for Aegis

Date recorded: 2026-10-27  
Station: Hades  
Written by: Argus, at Oliver's request  
Assigned to: Aegis  
Repository: `/Users/oliver/mac-forge`

## Why this note exists

Aldaris is becoming configurable in which engine and model serve it. The mac-forge side is built
(catalog under `configs/aldaris/catalog/`, profiles, `aldaris-configure`, engine adapters in
`scripts/aldaris-engines/`) but is still uncommitted on `refactor-optimize-ai-work`. Only LM Studio
works end to end. The `external` adapter exists for an OpenAI-compatible server started by hand, and
the two alternatives recorded for it are **oMLX** and **TensorFold**. Neither is installed yet.

This note is Aegis's next step: install both engines and verify them. Wiring them into the
catalog stays with Oliver/Argus.

## State on Hades at time of writing

- `/Volumes/dock-ssd/ai` contains `cache/` (`huggingface`, `tmp`, `torch`), `installers/`,
  `lmstudio/`, `models/`, `qwen/`, `tools/` (`qwen-code`), `verification/`.
- Free space: internal SSD 406 GiB, dock-ssd 1.4 TiB.
- No `uv` or `pipx`; only system Python 3.9.6 (`/usr/bin/python3`) and Homebrew
  (`/opt/homebrew`, internal SSD).
- LM Studio (port 1234) is the active Aldaris engine (profile `scenario-1`).

## Step: install and verify oMLX and TensorFold

### Storage rule (most important)

Everything that can live on the external drive goes under `/Volumes/dock-ssd/ai`, to keep the
internal SSD free:

- Engine installs, their Python environments and runtimes: `/Volumes/dock-ssd/ai/tools/omlx` and
  `/Volumes/dock-ssd/ai/tools/tensorfold`.
- Downloaded installers and archives: `/Volumes/dock-ssd/ai/installers`.
- Caches: `/Volumes/dock-ssd/ai/cache`. Set `HF_HOME`, `PIP_CACHE_DIR`, `UV_CACHE_DIR` (if uv is
  used), `XDG_CACHE_HOME` and `TMPDIR` to locations there for every install and run command.
- Model weights: `/Volumes/dock-ssd/ai/models`. Reuse the Qwen3.6-35B-A3B 8-bit weights already
  on dock-ssd (`mlx-community/Qwen3.6-35B-A3B-8bit`, revision
  `e06a74e6236a60c8367e1a3214e83d8b61b637b0`; LM Studio's model library points at dock-ssd). Do not
  download a second ~38 GB copy unless an engine cannot read the existing files; if that happens,
  stop and ask Oliver first.
- Don't use Homebrew, `~/.cache`, `~/Library/Caches` or `~/.local` for these tools. If something
  truly must go on the internal SSD (an app bundle in `/Applications`, a required system runtime),
  list it with its size and the reason, and get Oliver's approval before installing it.

### Before installing

1. Stop if `/Volumes/dock-ssd` is not mounted.
2. Confirm the official upstream source for oMLX and TensorFold: repository or site, install
   method, and macOS Apple Silicon support. If either one's identity or source is unclear, stop
   and report to Oliver instead of guessing.
3. Record internal SSD free space (`df -h /`).

### Install and verify

- Install each engine self-contained under its `tools/` folder, in a dedicated venv or with a
  bundled runtime. If a newer Python is needed, install it under dock-ssd too.
- For each engine, start the server bound to `127.0.0.1` on a port other than `1234`, load the
  existing Qwen MLX model, and confirm that `GET /v1/models` lists it and that one short chat
  completion succeeds.
- Then stop each engine completely and confirm nothing is left running (no daemons, launch agents
  or login items). Only one engine may use CPU/RAM at a time. Leave LM Studio and its
  configuration untouched.

### Boundaries

- Don't change the mac-forge repository other than writing the report below. The Aldaris
  configurability work there is uncommitted and in progress.
- Don't involve, launch or contact Aldaris.
- Don't run unit tests.

## Report back

Write the results to
`/Users/oliver/mac-forge/brainstorm/2026-10-27/aldaris-alternative-engines-aegis-report.md`
covering, for each engine:

- install path, version or commit, and upstream source used
- exact start and stop commands, including the environment variables used
- port, API key (if any), and the served model ID shown by `/v1/models`
- the model path it reads
- total disk use on dock-ssd
- anything placed on the internal SSD, with its size
- internal SSD free space before and after
- any blocker, or anything that needed Oliver's decision

## After Aegis reports

Argus/Oliver add the catalog entries: one engine file per server (e.g. `omlx.json`,
`tensorfold.json`, both using the `external` adapter) with the reported host, port and process
paths, plus `engines.<id>.servedId` on the Qwen model. Then do one live switch between LM Studio and
an external engine before committing.
