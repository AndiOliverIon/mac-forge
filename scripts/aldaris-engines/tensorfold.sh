# Adapter for TensorFold (Python engine 0.6.6), started and stopped by Aldaris itself. Contract and globals as in lmstudio.sh.
# engine_has_model and engine_stop need no active selection, so they derive paths from the catalog.
_tf_root() {
  local root
  root="$(jq -r '.storageRoot' "$FORGE_ROOT/configs/aldaris/catalog/global.json")" || return 1
  [[ -n "$root" && "$root" != null ]] || return 1
  printf '%s' "$root"
}

_tf_models() {
  curl -fsS --max-time 3 -H "Authorization: Bearer $API_KEY" "$BASE_URL/models" 2>/dev/null
}

engine_check() {
  local root; root="$(_tf_root)" || return 1
  [[ -x "$root/tools/tensorfold/venv/bin/python" ]] || { echo "TensorFold is missing ($root/tools/tensorfold/venv)." >&2; return 1; }
}

engine_has_model() {
  local root; root="$(_tf_root)" || return 2
  [[ -f "$root/models/$1/config.json" ]]
}

engine_probe() {
  if _tf_models >/dev/null; then
    echo "TensorFold server is answering at $BASE_URL."
  else
    echo "TensorFold server is not running; aldaris will start it."
  fi
}

# The engine has no idle-unload flag: the model stays resident until engine_stop. The prompt cache
# is capped at 16 GiB (the engine otherwise sizes it from free memory, ~62 GiB at 128K).
engine_ensure_running() {
  _tf_models >/dev/null && return 0
  local root dir cache; root="$(_tf_root)" || return 1
  dir="$root/tools/tensorfold"; cache="$root/cache"
  mkdir -p "$cache"/{xdg,tmp,hf}
  (
    cd "$dir" || exit 1
    export HF_HOME="$cache/hf" XDG_CACHE_HOME="$cache/xdg" TMPDIR="$cache/tmp" HF_HUB_OFFLINE=1
    nohup "$dir/venv/bin/python" -m tensorfold serve "$root/models/$MODEL_KEY" \
      --host "$HOST" --port "$PORT" --name "$MODEL" --context "$CONTEXT_LENGTH" \
      --api-key "$API_KEY" --parallel 1 --max-tokens 8192 --prompt-cache-gib 16 --no-update-check \
      > "$dir/server.log" 2>&1 < /dev/null &
    echo $! > "$dir/server.pid"
  )
  local i
  for ((i = 0; i < 120; i++)); do
    _tf_models >/dev/null && return 0
    sleep 1
  done
  echo "TensorFold did not answer within 120 s; see $dir/server.log." >&2
  return 1
}

# The model is loaded at start; here we only confirm it is served.
engine_ensure_loaded() {
  _tf_models | jq -e --arg id "$MODEL" '.data[]? | select(.id == $id)' >/dev/null \
    || { echo "TensorFold does not list '$MODEL' at $BASE_URL/models." >&2; return 1; }
}

# Identity comes from the executable the process runs (inside tools/tensorfold), not its title.
_tf_is_ours() {
  lsof -p "$1" -a -d txt -Fn 2>/dev/null | grep -q "^n$2/"
}

# Kills only the recorded PID, and only while it still runs an executable from tools/tensorfold.
engine_stop() {
  local root dir pidfile pid i; root="$(_tf_root)" || return 0
  dir="$root/tools/tensorfold"; pidfile="$dir/server.pid"
  [[ -f "$pidfile" ]] || return 0
  pid="$(<"$pidfile")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && _tf_is_ours "$pid" "$dir"; then
    kill "$pid" 2>/dev/null || true
    for ((i = 0; i < 30; i++)); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "TensorFold (pid $pid) did not stop; stop it manually." >&2
      return 1
    fi
  fi
  rm -f "$pidfile"
  return 0
}
