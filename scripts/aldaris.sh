#!/usr/bin/env bash
set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$FORGE_ROOT/configs/aldaris/config.json"
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }
AI_ROOT="$(jq -r .storageRoot "$CONFIG")"
BASE_URL="$(jq -r .baseUrl "$CONFIG")"
MODEL="$(jq -r .model "$CONFIG")"
CONTEXT_LENGTH="$(jq -r .contextLength "$CONFIG")"
LMS="$HOME/.lmstudio/bin/lms"
QWEN="$AI_ROOT/tools/qwen-code/bin/qwen"

/sbin/mount | /usr/bin/grep -Fq " on $(dirname "$AI_ROOT") (" || {
  echo "Mount $(dirname "$AI_ROOT") before starting Aldaris." >&2; exit 1;
}
[[ -x "$LMS" && -x "$QWEN" ]] || { echo "LM Studio or Qwen Code is missing." >&2; exit 1; }

# Embed the shared base set in the same order as ai-config's render_bootstrap; the resolver omits it.
SHARED_AI="$FORGE_ROOT/.config/ai"
# Every read failure returns nonzero: set -e does not apply inside the command substitution below.
shared_base() {
  local relative_path source_path always_count=0
  for relative_path in identities.md guidelines/guidelines.md; do
    printf '\n\n# Embedded source: ~/.config/ai/%s\n\n' "$relative_path"
    cat "$SHARED_AI/$relative_path" || return 1
  done
  while IFS= read -r source_path; do
    printf '\n\n# Embedded source: ~/.config/ai/%s\n\n' "${source_path#"$SHARED_AI/"}"
    cat "$source_path" || return 1
    always_count=$((always_count + 1))
  done < <(find "$SHARED_AI/guidelines/always" -maxdepth 1 -type f -name '*.md' -print | LC_ALL=C sort)
  (( always_count > 0 ))
}
for required in "$FORGE_ROOT/configs/aldaris/instructions.md" "$SHARED_AI/identities.md" \
    "$SHARED_AI/guidelines/guidelines.md" "$SHARED_AI/guidelines/always"; do
  [[ -r "$required" ]] || { echo "Missing Aldaris instructions: $required" >&2; exit 1; }
done
SYSTEM_PROMPT="$(cat "$FORGE_ROOT/configs/aldaris/instructions.md" && shared_base)" || {
  echo "Could not read every shared AI instruction under $SHARED_AI; Aldaris was not started." >&2; exit 1;
}

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
loaded_models="$("$LMS" ps --json)"
if ! jq -e --arg id "$MODEL" --argjson context "$CONTEXT_LENGTH" \
    '.[] | select(.identifier == $id and .contextLength == $context)' <<< "$loaded_models" >/dev/null; then
  if jq -e --arg id "$MODEL" '.[] | select(.identifier == $id)' <<< "$loaded_models" >/dev/null; then
    if jq -e --arg id "$MODEL" '.[] | select(.identifier == $id and (.status != "idle" or .queued > 0))' <<< "$loaded_models" >/dev/null; then
      echo "Aldaris is busy with a different context size. Retry after the current request finishes." >&2
      exit 1
    fi
    "$LMS" unload "$MODEL"
  fi
  "$LMS" load "$(jq -r .modelKey "$CONFIG")" --identifier "$MODEL" \
    --context-length "$CONTEXT_LENGTH" --parallel 1 \
    --ttl "$(jq -r .idleSeconds "$CONFIG")" --yes
fi

exec "$QWEN" --auth-type openai --openai-base-url "$BASE_URL" \
  --openai-api-key lm-studio --model "$MODEL" \
  --append-system-prompt "$SYSTEM_PROMPT" "$@"
