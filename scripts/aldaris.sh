#!/usr/bin/env bash
set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$FORGE_ROOT/configs/aldaris/config.json"
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }
AI_ROOT="$(jq -r .storageRoot "$CONFIG")"
BASE_URL="$(jq -r .baseUrl "$CONFIG")"
MODEL="$(jq -r .model "$CONFIG")"
LMS="$HOME/.lmstudio/bin/lms"
QWEN="$AI_ROOT/tools/qwen-code/bin/qwen"

/sbin/mount | /usr/bin/grep -Fq " on $(dirname "$AI_ROOT") (" || {
  echo "Mount $(dirname "$AI_ROOT") before starting Aldaris." >&2; exit 1;
}
[[ -x "$LMS" && -x "$QWEN" ]] || { echo "LM Studio or Qwen Code is missing." >&2; exit 1; }

export QWEN_HOME="$AI_ROOT/qwen"
export HF_HOME="$AI_ROOT/cache/huggingface"
export HUGGINGFACE_HUB_CACHE="$HF_HOME/hub"
export TORCH_HOME="$AI_ROOT/cache/torch"
export TMPDIR="$AI_ROOT/cache/tmp"
export QWEN_USAGE_STATISTICS_ENABLED=false
mkdir -p "$QWEN_HOME" "$TMPDIR"

if ! curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; then
  "$LMS" server start --bind 127.0.0.1 --port 1234
fi
if ! "$LMS" ps --json | jq -e --arg id "$MODEL" '.[] | select(.identifier == $id)' >/dev/null; then
  "$LMS" load "$(jq -r .modelKey "$CONFIG")" --identifier "$MODEL" \
    --context-length "$(jq -r .contextLength "$CONFIG")" --parallel 1 \
    --ttl "$(jq -r .idleSeconds "$CONFIG")" --yes
fi

exec "$QWEN" --auth-type openai --openai-base-url "$BASE_URL" \
  --openai-api-key lm-studio --model "$MODEL" \
  --append-system-prompt "$(cat "$FORGE_ROOT/configs/aldaris/instructions.md")" "$@"
