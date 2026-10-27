# Sourced by aldaris.sh and aldaris-configure.sh. Requires FORGE_ROOT and jq.
ALDARIS_ACTIVE="$FORGE_ROOT/config-local/aldaris/active.json"
ALDARIS_DEFAULT_PROFILE="scenario-1"
ALDARIS_CONFIG="$FORGE_ROOT/scripts/agents/aldaris_config.py"

aldaris_config() { /usr/bin/python3 "$ALDARIS_CONFIG" "$@"; }

# Loads one resolved selection into globals and sources its engine adapter.
aldaris_load_active() {
  local file="${1:-$ALDARIS_ACTIVE}"
  [[ -f "$file" ]] || { echo "No active Aldaris configuration; run aldaris-configure." >&2; return 1; }
  jq -e '.engine and .adapter and .model and .baseUrl and .host and .port and .contextLength and .idleSeconds and .storageRoot and (.apiKey|type=="string") and (.modelKey|type=="string") and (.modelPath|type=="string")' \
    "$file" >/dev/null || { echo "Invalid $file; run aldaris-configure." >&2; return 1; }
  ENGINE="$(jq -r .engine "$file")"
  ADAPTER="$(jq -r .adapter "$file")"
  MODEL="$(jq -r .model "$file")"
  MODEL_KEY="$(jq -r .modelKey "$file")"
  MODEL_PATH="$(jq -r .modelPath "$file")"
  BASE_URL="$(jq -r .baseUrl "$file")"
  HOST="$(jq -r .host "$file")"
  PORT="$(jq -r .port "$file")"
  API_KEY="$(jq -r .apiKey "$file")"
  CONTEXT_LENGTH="$(jq -r .contextLength "$file")"
  IDLE_SECONDS="$(jq -r .idleSeconds "$file")"
  AI_ROOT="$(jq -r .storageRoot "$file")"
  PROFILE_NAME="$(jq -r '.profile // "unsaved"' "$file")"
  [[ "$ADAPTER" =~ ^[a-z0-9-]+$ && -f "$FORGE_ROOT/scripts/aldaris-engines/$ADAPTER.sh" ]] \
    || { echo "Unknown engine adapter '$ADAPTER'." >&2; return 1; }
  # shellcheck source=/dev/null
  source "$FORGE_ROOT/scripts/aldaris-engines/$ADAPTER.sh"
}

# Without an active selection, resolve and apply the default profile.
aldaris_ensure_active() {
  [[ -f "$ALDARIS_ACTIVE" ]] && return 0
  echo "No active Aldaris configuration; applying $ALDARIS_DEFAULT_PROFILE." >&2
  aldaris_config resolve --profile "$ALDARIS_DEFAULT_PROFILE" | aldaris_config apply --yes >&2
}

# Gracefully stops one engine through its adapter; needs no active selection.
aldaris_stop_engine() {
  local adapter="$1"
  [[ "$adapter" =~ ^[a-z0-9-]+$ && -f "$FORGE_ROOT/scripts/aldaris-engines/$adapter.sh" ]] || return 0
  ( source "$FORGE_ROOT/scripts/aldaris-engines/$adapter.sh"; engine_stop ) || true
}

# Only the active configuration may hold resources: stop every other catalog engine.
aldaris_stop_others() {
  local keep="$1" id adapter
  while IFS=$'\t' read -r id adapter; do
    [[ "$id" == "$keep" ]] || aldaris_stop_engine "$adapter"
  done < <(aldaris_config engines)
  aldaris_config stop-processes --except "$keep"
}
