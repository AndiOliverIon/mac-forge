# Adapter for an OpenAI-compatible server that Oliver starts and loads himself (oMLX, TensorFold, ...).
# Contract and globals as in lmstudio.sh.
engine_check() { return 0; }

engine_has_model() { return 2; }

_external_models() {
  curl -fsS --max-time 3 -H "Authorization: Bearer $API_KEY" "$BASE_URL/models" 2>/dev/null
}

engine_probe() {
  if _external_models >/dev/null; then
    echo "Server answers at $BASE_URL."
  else
    echo "No server answers at $BASE_URL; start the engine yourself before running aldaris."
  fi
}

engine_ensure_running() {
  _external_models >/dev/null || {
    echo "No server answers at $BASE_URL. Start the '$ENGINE' engine first." >&2
    return 1
  }
}

engine_ensure_loaded() {
  _external_models | jq -e --arg id "$MODEL" '.data[]? | select(.id == $id)' >/dev/null \
    || echo "Warning: '$MODEL' is not listed by $BASE_URL/models; continuing." >&2
  return 0
}

# Not stoppable here: this engine is started by hand. Only its catalog paths are killed, if any.
engine_stop() { return 0; }
