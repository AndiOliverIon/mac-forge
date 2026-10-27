# Adapter contract: engine_check, engine_has_model <key> (0 yes, 1 no, 2 unknown), engine_probe,
# engine_ensure_running, engine_ensure_loaded, engine_stop. engine_stop needs no active selection;
# the rest use globals from aldaris_load_active.
LMS="$HOME/.lmstudio/bin/lms"

engine_check() {
  [[ -x "$LMS" ]] || { echo "LM Studio is missing ($LMS)." >&2; return 1; }
}

engine_has_model() {
  "$LMS" ls --json 2>/dev/null | jq -e --arg key "$1" '.[] | select(.modelKey == $key)' >/dev/null
}

engine_probe() {
  if curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; then
    echo "LM Studio server is answering at $BASE_URL."
  else
    echo "LM Studio server is not running; aldaris will start it."
  fi
}

engine_ensure_running() {
  if ! curl -fsS --max-time 2 "$BASE_URL/models" >/dev/null 2>&1; then
    "$LMS" server start --bind "$HOST" --port "$PORT"
  fi
}

# Only the active model may stay resident: every other loaded model is unloaded unless it is busy.
engine_ensure_loaded() {
  local loaded exact_filter='(.identifier == $id and .contextLength == $ctx and ((.modelKey // "") == $key or (.path // "") == $path))'
  loaded="$("$LMS" ps --json)"
  if jq -e --arg id "$MODEL" --argjson ctx "$CONTEXT_LENGTH" --arg key "$MODEL_KEY" --arg path "$MODEL_PATH" \
      ".[] | select(($exact_filter | not) and (.status != \"idle\" or .queued > 0))" <<< "$loaded" >/dev/null; then
    echo "LM Studio is busy with another model or context. Retry after the current request finishes." >&2
    return 1
  fi
  local identifier
  while IFS= read -r identifier; do
    [[ -n "$identifier" ]] && "$LMS" unload "$identifier"
  done < <(jq -r --arg id "$MODEL" --argjson ctx "$CONTEXT_LENGTH" --arg key "$MODEL_KEY" --arg path "$MODEL_PATH" \
      ".[] | select($exact_filter | not) | .identifier" <<< "$loaded")
  if jq -e --arg id "$MODEL" --argjson ctx "$CONTEXT_LENGTH" --arg key "$MODEL_KEY" --arg path "$MODEL_PATH" \
      ".[] | select($exact_filter)" <<< "$loaded" >/dev/null; then
    return 0
  fi
  "$LMS" load "$MODEL_KEY" --identifier "$MODEL" \
    --context-length "$CONTEXT_LENGTH" --parallel 1 --ttl "$IDLE_SECONDS" --yes
}

# Graceful full stop: unload every model, stop the server and the daemon, quit the app.
engine_stop() {
  [[ -x "$LMS" ]] || return 0
  if pgrep -f "/Applications/LM Studio.app/|/\.lmstudio/" >/dev/null 2>&1; then
    "$LMS" unload --all >/dev/null 2>&1 || true
    "$LMS" server stop >/dev/null 2>&1 || true
    "$LMS" daemon down >/dev/null 2>&1 || true
  fi
  if [[ "$(osascript -e 'application "LM Studio" is running' 2>/dev/null)" == "true" ]]; then
    osascript -e 'tell application "LM Studio" to quit' >/dev/null 2>&1 || true
  fi
  return 0
}
