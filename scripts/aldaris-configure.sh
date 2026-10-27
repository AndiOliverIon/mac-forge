#!/usr/bin/env bash
set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aldaris-lib.sh
source "$FORGE_ROOT/scripts/aldaris-lib.sh"
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

usage() {
  cat >&2 <<'USAGE'
Usage: aldaris-configure                    interactive picker (engine, model, context, preset)
       aldaris-configure list               saved profiles
       aldaris-configure show               active configuration
       aldaris-configure status             drift check of outside files
       aldaris-configure apply <profile> [--yes]
       aldaris-configure save <name>        save the active configuration as a profile
       aldaris-configure clean <engine>     remove files/keys recorded for an engine
       aldaris-configure stop               free every CPU/RAM resource Aldaris uses (alias: aldaris-stop)
USAGE
  exit 2
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pick() {
  local header="$1" preview="${2:-}"
  local args=(--delimiter=$'\t' --with-nth=2.. --header "$header" --height=60% --reverse --no-multi)
  [[ -z "$preview" ]] || args+=(--preview "$preview" --preview-window=right:55%)
  fzf "${args[@]}" | cut -f1
}

# Rows are "id<TAB>text..."; fzf hides the id column.
rows() { awk -F'\t' '{ printf "%s\t", $1; for (i = 2; i <= NF; i++) printf "%s%s", $i, (i < NF ? "  " : ""); printf "\n" }'; }

engine_adapter() { aldaris_config catalog engines "$1" | jq -r .adapter; }

model_rows() {
  local engine="$1" adapter line key marker state
  adapter="$(engine_adapter "$engine")"
  while IFS=$'\t' read -r id desc quant size key; do
    marker="[missing]"
    (source "$FORGE_ROOT/scripts/aldaris-engines/$adapter.sh"; engine_has_model "$key") 2>/dev/null && state=0 || state=$?
    case "$state" in
      0) marker="[installed]" ;;
      2) marker="[unverified]" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$desc" "$quant" "$size" "$marker"
  done < <(aldaris_config list models --engine "$engine")
}

confirm_preview() {
  jq -r '"Engine:  \(.engine) (\(.baseUrl))\nModel:   \(.modelId) -> \(.model)\nContext: \(.contextLength)\nPreset:  \(.preset)\n"' "$1"
  aldaris_config apply --dry-run < "$1" 2>&1
}

check_ready() {
  local file="$1"
  (
    aldaris_load_active "$file"
    engine_check
    local state=0
    [[ -z "$MODEL_KEY" ]] || engine_has_model "$MODEL_KEY" || state=$?
    if [[ "$state" -eq 1 ]]; then
      echo "Model '$MODEL_KEY' is not installed in engine '$ENGINE'. Install it there first; nothing was changed." >&2
      exit 1
    fi
  )
}

apply_resolved() {
  local file="$1" yes="${2:-}"
  check_ready "$file"
  aldaris_stop_others "$(jq -r .engine "$file")"
  aldaris_config apply ${yes:+"$yes"} < "$file"
  (aldaris_load_active; engine_probe) || true
  echo "Aldaris configured: $(jq -r '"\(.engine) / \(.modelId) / \(.contextLength) context / \(.preset)"' "$ALDARIS_ACTIVE")"
}

stop_all() {
  local id adapter
  while IFS=$'\t' read -r id adapter; do
    aldaris_stop_engine "$adapter"
  done < <(aldaris_config engines 2>/dev/null || true)
  aldaris_config stop-processes 2>/dev/null || true
  local remaining
  if remaining="$(/usr/bin/python3 "$FORGE_ROOT/scripts/agents/aldaris-monitor.py" --check-idle 2>&1)"; then
    echo "Aldaris stopped; nothing resident."
  else
    echo "Still resident:" >&2
    printf '%s\n' "$remaining" | awk -F'\t' '{ print "  " $1 "  " $2 }' >&2
    return 1
  fi
}

interactive() {
  command -v fzf >/dev/null || { echo "fzf is required." >&2; exit 1; }
  local choice profile="" engine model context preset resolved="$TMP/resolved.json"
  choice="$( { aldaris_config list profiles | awk -F'\t' '{ printf "profile:%s\tSaved  %s  %s\n", $1, $1, $2 }'; printf 'new\tNew configuration\n'; } \
    | pick "Aldaris: saved configuration or new" "")" || true
  [[ -n "$choice" ]] || { echo "Cancelled." >&2; exit 1; }
  if [[ "$choice" == profile:* ]]; then
    profile="${choice#profile:}"
    aldaris_config resolve --profile "$profile" > "$resolved"
  else
    engine="$(aldaris_config list engines | rows | pick "Engine" "/usr/bin/python3 $ALDARIS_CONFIG catalog engines {1}")" || true
    [[ -n "$engine" ]] || { echo "Cancelled." >&2; exit 1; }
    model="$(model_rows "$engine" | rows | pick "Model (engine: $engine)" "/usr/bin/python3 $ALDARIS_CONFIG catalog models {1}")" || true
    [[ -n "$model" ]] || { echo "Cancelled (or no model fits engine '$engine')." >&2; exit 1; }
    context="$(aldaris_config contexts "$model" | awk '{ print $1 "\t" $1 " tokens" }' | pick "Context (model: $model)" "")" || true
    [[ -n "$context" ]] || { echo "Cancelled." >&2; exit 1; }
    preset="$(aldaris_config list presets | rows | pick "Sampling preset" "/usr/bin/python3 $ALDARIS_CONFIG catalog presets {1}")" || true
    [[ -n "$preset" ]] || { echo "Cancelled." >&2; exit 1; }
    aldaris_config resolve --engine "$engine" --model "$model" --context "$context" --preset "$preset" > "$resolved"
  fi
  choice="$(printf 'apply\tApply\ncancel\tCancel\n' | pick "Confirm" "$FORGE_ROOT/scripts/aldaris-configure.sh __preview $resolved")" || true
  [[ "$choice" == apply ]] || { echo "Cancelled; nothing changed." >&2; exit 1; }
  apply_resolved "$resolved"
  if [[ -z "$profile" ]]; then
    choice="$(printf 'no\tNo\nyes\tSave as a named profile\n' | pick "Save this configuration?" "")" || true
    if [[ "$choice" == yes ]]; then
      read -r -p "Profile name: " profile
      aldaris_config save "$profile"
    fi
  fi
}

case "${1:-}" in
  "") interactive ;;
  list) aldaris_config list profiles ;;
  show) jq '.apiKey |= (if . == "" then . else "<redacted>" end)' "$ALDARIS_ACTIVE" 2>/dev/null || { echo "No active Aldaris configuration." >&2; exit 1; } ;;
  status) aldaris_config status ;;
  apply)
    [[ $# -ge 2 ]] || usage
    aldaris_config resolve --profile "$2" > "$TMP/resolved.json"
    apply_resolved "$TMP/resolved.json" "${3:-}"
    ;;
  save) [[ $# -eq 2 ]] || usage; aldaris_config save "$2" ;;
  clean) [[ $# -eq 2 ]] || usage; aldaris_config clean "$2" ;;
  stop) stop_all ;;
  __preview) confirm_preview "$2" ;;
  *) usage ;;
esac
