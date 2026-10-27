# Aldaris alternative engines — Aegis report

Date: 2026-10-27 · Station: Hades · Author: Aegis

## Summary

- **oMLX: installed and verified** (`/v1/models` lists the Qwen model; one chat completion succeeded).
- **TensorFold: installed, but cannot serve the Qwen3.6-35B-A3B 8-bit weights.** Needs Oliver's decision.
- Both engines are stopped; nothing is running, no launch agents or login items. LM Studio untouched.
- Internal SSD free space: 406 GiB before and after (`df -h /`). Nothing was placed on it.

## Source identification

- oMLX: https://github.com/jundot/omlx (site omlx.ai), release `v0.7.3.dev2`. macOS 15+, Apple Silicon.
- TensorFold: https://github.com/ashhart/TensorFold (site tensorfold.dev), Apache-2.0, release `v1.1.6`.
  A web search first suggested `meta-llama/tensorfold`; that URL returns 404 and was ignored.
  The README states macOS Apple Silicon support.

## oMLX

- Install path: `/Volumes/dock-ssd/ai/tools/omlx/`
  - `python312/` — python-build-standalone CPython 3.12.16 (release 20261026, from `installers/`)
  - `venv/` — venv with `omlx-0.7.3.dev2` installed from the release wheel
    `installers/omlx-0.7.3.dev2-cp312-cp312-macosx_15_0_universal2.whl`
  - `base/` — `--base-path` (settings.json, logs, paged SSD cache)
  - `models/mlx-community/Qwen3.6-35B-A3B-8bit` — symlink to the existing weights (no copy)
- Model path read: `/Volumes/dock-ssd/ai/lmstudio/models/mlx-community/Qwen3.6-35B-A3B-8bit`
- Start (from `/Volumes/dock-ssd/ai/tools/omlx`):

  ```sh
  A=/Volumes/dock-ssd/ai
  export PIP_CACHE_DIR=$A/cache/pip XDG_CACHE_HOME=$A/cache/xdg TMPDIR=$A/cache/tmp HF_HOME=$A/cache/hf
  nohup $A/tools/omlx/venv/bin/omlx serve \
    --model-dir $A/tools/omlx/models --base-path $A/tools/omlx/base \
    --host 127.0.0.1 --port 8000 --api-key aldaris-local \
    --paged-ssd-cache-dir $A/tools/omlx/base/cache > $A/tools/omlx/server.log 2>&1 &
  echo $! > $A/tools/omlx/server.pid
  ```

- Stop: `kill "$(cat /Volumes/dock-ssd/ai/tools/omlx/server.pid)"` (no daemon; foreground process).
- Port: `127.0.0.1:8000`. API key: `aldaris-local` (placeholder I chose; send as `Authorization: Bearer aldaris-local`).
- Served model ID: `Qwen3.6-35B-A3B-8bit` (context 262144).
- Chat check: succeeded, ~77 tok/s, first load ~13 s. The model is a reasoning model: with `max_tokens: 64`
  the output was all `reasoning_content` and `finish_reason: length`; clients need a larger limit.
- Quirk: on start, oMLX writes a symlink `~/.omlx/bin/omlx-cluster-python` (ignores `--base-path`).
  It is a 0-byte-cost symlink; I removed it and `~/.omlx` after the run. It will reappear on each start.
- Warning logged: Metal cap 107.5 GB is below oMLX's 120 GB ceiling because `iogpu.wired_limit_mb` is unset. Harmless; no sysctl changed.
- Disk on dock-ssd: `tools/omlx` 1.5 GB.

## TensorFold

- Install path: `/Volumes/dock-ssd/ai/tools/tensorfold/`
  - `tensorfold-1.1.6-macos-arm64/` — native Zig release, sha256 verified against the published `.sha256`
    (archive kept in `installers/`). Binary: `bin/tensorfold-native`.
  - `venv-py066/` — Python engine `tensorfold 0.6.6` (from `git+https://github.com/ashhart/TensorFold.git@v0.6.6`,
    with mlx 0.32.3 / mlx-lm 0.32.2), installed because the native engine suggested it.
- Attempted start (port 8002, bound to 127.0.0.1):
  - Native: `tensorfold-native serve <model dir> --host 127.0.0.1 --port 8002 --name Qwen3.6-35B-A3B-8bit --context 8192 --no-thinking --no-update-check`
    → `the native engine has no backend for qwen3_5_moe checkpoints yet`.
  - Python 0.6.6: same arguments via `venv-py066/bin/python -m tensorfold serve …`
    → `Qwen3.6 MoE's CUDA engine reads MLX 4-bit weights in groups of 64 (TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP); this checkpoint has MLX 8-bit`.
  Both exit immediately; the server never started, so no `/v1/models` or chat result exists.
- Port / API key / served ID: not reached (planned 8002, no key, `--name Qwen3.6-35B-A3B-8bit`).
- Model path it would read: `/Volumes/dock-ssd/ai/lmstudio/models/mlx-community/Qwen3.6-35B-A3B-8bit`.
- Disk on dock-ssd: `tools/tensorfold` 466 MB.
- Environment used: `HF_HOME`, `XDG_CACHE_HOME`, `TMPDIR`, `PIP_CACHE_DIR` under `/Volumes/dock-ssd/ai/cache`.

## Disk summary (dock-ssd, `/Volumes/dock-ssd/ai`)

| Item | Size |
| --- | --- |
| `tools/omlx` | 1.5 GB |
| `tools/tensorfold` | 466 MB |
| `installers` (incl. pre-existing LM Studio dmg) | 612 MB |
| `cache` | 444 MB |

No model weights were downloaded or copied.

## Decisions needed from Oliver

1. TensorFold cannot run this Qwen 8-bit checkpoint. Options: (a) drop TensorFold for Aldaris; (b) test it with a
   TensorFold-supported checkpoint, e.g. `TensorFold/Qwen3.6-35B-A3B-MLX-4bit-MTP` (needs a new download, size
   not checked; I did not download it per the "ask first" rule); (c) write a recipe for the 8-bit model.
2. oMLX API key: keep `aldaris-local` or choose another before it goes into the catalog.

## Catalog hints

- `omlx`: `external` adapter, host `127.0.0.1`, port `8000`, `servedId` `Qwen3.6-35B-A3B-8bit`, start/stop as above, bearer key required.
