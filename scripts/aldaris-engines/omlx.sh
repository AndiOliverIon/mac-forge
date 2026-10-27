# Adapter for oMLX, started and stopped by Aldaris itself. Contract and globals as in lmstudio.sh.
# engine_has_model and engine_stop need no active selection, so they derive paths from the catalog.
_omlx_root() {
  local root
  root="$(jq -r '.storageRoot' "$FORGE_ROOT/configs/aldaris/catalog/global.json")" || return 1
  [[ -n "$root" && "$root" != null ]] || return 1
  printf '%s/tools/omlx' "$root"
}

_omlx_models() {
  curl -fsS --max-time 3 -H "Authorization: Bearer $API_KEY" "$BASE_URL/models" 2>/dev/null
}

engine_check() {
  local dir; dir="$(_omlx_root)" || return 1
  [[ -x "$dir/venv/bin/omlx" ]] || { echo "oMLX is missing ($dir/venv/bin/omlx)." >&2; return 1; }
}

engine_has_model() {
  local dir; dir="$(_omlx_root)" || return 2
  [[ -e "$dir/models/$1" ]]
}

engine_probe() {
  if _omlx_models >/dev/null; then
    echo "oMLX server is answering at $BASE_URL."
  else
    echo "oMLX server is not running; aldaris will start it."
  fi
}

# Applies the context cap and idle unload through settings.json (oMLX has no flags for them).
_omlx_apply_settings() {
  local file="$1" tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp "$file.XXXXXX")" || return 1
  if jq --argjson idle "$IDLE_SECONDS" --argjson ctx "$CONTEXT_LENGTH" \
      '.idle_timeout.idle_timeout_seconds = $idle | .sampling.max_context_window_policy = $ctx
       | .scheduler.max_concurrent_requests = 1 | .server.gpu_keep_warm_interval = 0' "$file" > "$tmp"; then
    chmod 600 "$tmp"
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

engine_ensure_running() {
  _omlx_models >/dev/null && return 0
  local dir cache; dir="$(_omlx_root)" || return 1
  cache="$(dirname "$dir")/cache"
  mkdir -p "$cache"/{pip,xdg,tmp,hf} "$dir/base"
  _omlx_apply_settings "$dir/base/settings.json" || return 1
  (
    cd "$dir" || exit 1
    export PIP_CACHE_DIR="$cache/pip" XDG_CACHE_HOME="$cache/xdg" TMPDIR="$cache/tmp" HF_HOME="$cache/hf"
    nohup "$dir/venv/bin/omlx" serve --model-dir "$dir/models" --base-path "$dir/base" \
      --host "$HOST" --port "$PORT" --api-key "$API_KEY" --paged-ssd-cache-dir "$dir/base/cache" \
      > "$dir/server.log" 2>&1 < /dev/null &
    echo $! > "$dir/server.pid"
  )
  local i
  for ((i = 0; i < 60; i++)); do
    _omlx_models >/dev/null && return 0
    sleep 1
  done
  echo "oMLX did not answer within 60 s; see $dir/server.log." >&2
  return 1
}

# oMLX loads the model on the first request; here we only confirm it is served.
engine_ensure_loaded() {
  _omlx_models | jq -e --arg id "$MODEL" '.data[]? | select(.id == $id)' >/dev/null \
    || { echo "oMLX does not list '$MODEL' at $BASE_URL/models." >&2; return 1; }
}

# oMLX renames its process title, so identity comes from the executable it runs (inside tools/omlx).
_omlx_is_ours() {
  local pid="$1" dir="$2"
  lsof -p "$pid" -a -d txt -Fn 2>/dev/null | grep -q "^n$dir/"
}

# Kills only the recorded PID, and only while it still runs an executable from tools/omlx.
engine_stop() {
  local dir pidfile pid i; dir="$(_omlx_root)" || return 0
  pidfile="$dir/server.pid"
  if [[ -f "$pidfile" ]]; then
    pid="$(<"$pidfile")"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      if _omlx_is_ours "$pid" "$dir"; then
        kill "$pid" 2>/dev/null || true
        for ((i = 0; i < 30; i++)); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
          echo "oMLX (pid $pid) did not stop; stop it manually." >&2
          return 1
        fi
      fi
    fi
    rm -f "$pidfile"
  fi
  # oMLX leaves only bin/omlx-cluster-python in ~/.omlx; anything else there is not ours to remove.
  if [[ -d "$HOME/.omlx" && ! -L "$HOME/.omlx" ]] \
      && [[ "$(find "$HOME/.omlx" -mindepth 1 ! -path "$HOME/.omlx/bin" ! -path "$HOME/.omlx/bin/omlx-cluster-python" | wc -l | tr -d ' ')" == 0 ]]; then
    rm -f "$HOME/.omlx/bin/omlx-cluster-python"
    rmdir "$HOME/.omlx/bin" "$HOME/.omlx" 2>/dev/null || true
  fi
  return 0
}
