#!/usr/bin/env bash
set -euo pipefail

# Experimental: Claude Code backed by a local Ollama model instead of Anthropic.
OLLAMA_URL="${ALDARIS_OLLAMA_URL:-http://localhost:11434}"
CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/configs/aldaris/config.json"
MODEL="${ALDARIS_MODEL:-$(jq -r .model "$CONFIG")}"

command -v claude >/dev/null || { echo "claude CLI not found." >&2; exit 1; }
command -v ollama >/dev/null || { echo "ollama not found." >&2; exit 1; }

if ! curl -fsS --max-time 3 "$OLLAMA_URL/api/version" >/dev/null 2>&1; then
  echo "Ollama is not reachable at $OLLAMA_URL. Start it with 'ollama serve' or the Ollama app." >&2
  exit 1
fi

if ! ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "$MODEL"; then
  echo "Model $MODEL is not downloaded. Pull it with: ollama pull $MODEL" >&2
  exit 1
fi

export ANTHROPIC_BASE_URL="$OLLAMA_URL"
export ANTHROPIC_AUTH_TOKEN="ollama"
unset ANTHROPIC_API_KEY
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="${OLLAMA_CONTEXT_LENGTH:-65536}"

exec claude --model "$MODEL" "$@"
