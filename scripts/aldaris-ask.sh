#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${ALDARIS_CONFIG:-$FORGE_ROOT/configs/aldaris.json}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mac-forge"
LOG_FILE="$LOG_DIR/aldaris.jsonl"
LEVELS=(trivial standard moderate high)
VERDICTS=(accepted corrected rejected)

usage() {
    cat <<'EOF'
Delegate one bounded, non-agentic step to Aldaris (local Ollama model).

Usage:
  aldaris-ask --caller NAME --level LEVEL --task TEXT [--file PATH|- ...]
  aldaris-ask --verdict ID accepted|corrected|rejected [--note TEXT]
  aldaris-ask --stats

Options:
  --caller NAME   Delegating identity; must be listed in configs/aldaris.json.
  --level LEVEL   trivial, standard, moderate, or high; must not exceed maxLevel.
  --task TEXT     Instruction for Aldaris.
  --file PATH     Input file; repeatable. Use - to read piped stdin.
  --verdict ID V  Record how the caller used the response.
  --note TEXT     Optional short reason for a verdict.
  --stats         Summarize the delegation log by level and verdict.

Aldaris only returns text; it never reads or edits files itself.
Log: ~/.local/state/mac-forge/aldaris.jsonl
EOF
}

die() { echo "aldaris-ask: $*" >&2; exit 1; }

level_rank() {
    local i
    for i in "${!LEVELS[@]}"; do
        [[ "${LEVELS[$i]}" == "$1" ]] && { echo "$i"; return; }
    done
    echo -1
}

cfg() { jq -r "$1" "$CONFIG"; }

record_verdict() {
    local id="$1" verdict="$2" note="$3"
    [[ " ${VERDICTS[*]} " == *" $verdict "* ]] || die "verdict must be one of: ${VERDICTS[*]}"
    [[ -f "$LOG_FILE" ]] && grep -Fq "\"id\":\"$id\"" "$LOG_FILE" || die "unknown delegation id: $id"
    jq -cn --arg id "$id" --arg verdict "$verdict" --arg note "$note" \
        --arg at "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
        '{type:"verdict", id:$id, verdict:$verdict, note:$note, at:$at}' >> "$LOG_FILE"
    echo "[ALDARIS] verdict recorded: $id → $verdict"
}

show_stats() {
    [[ -f "$LOG_FILE" ]] || { echo "No Aldaris delegations logged yet."; return; }
    jq -rs '
        (map(select(.type == "verdict")) | map({key: .id, value: .verdict}) | from_entries) as $v
        | map(select(.type == "delegation"))
        | "Delegations: \(length)",
          (group_by(.level)[] | . as $g
            | "  \($g[0].level): \($g | length) total, "
              + (["accepted","corrected","rejected","pending"] | map(. as $k
                  | "\($k) \([$g[] | ($v[.id] // "pending")] | map(select(. == $k)) | length)") | join(", "))
              + ", avg \(([$g[].durationSeconds] | add / length * 10 | round / 10))s")
    ' "$LOG_FILE"
}

caller="" level="" task="" verdict_id="" verdict="" note=""
files=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --caller) caller="${2:-}"; shift 2 ;;
        --level) level="${2:-}"; shift 2 ;;
        --task) task="${2:-}"; shift 2 ;;
        --file) files+=("${2:-}"); shift 2 ;;
        --verdict) verdict_id="${2:-}"; verdict="${3:-}"; shift 3 || die "--verdict needs ID and value" ;;
        --note) note="${2:-}"; shift 2 ;;
        --stats) show_stats; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null || die "jq is required."
[[ -f "$CONFIG" ]] || die "config not found: $CONFIG"
mkdir -p "$LOG_DIR"

if [[ -n "$verdict_id" ]]; then
    record_verdict "$verdict_id" "$verdict" "$note"
    exit 0
fi

[[ -n "$caller" && -n "$level" && -n "$task" ]] || { usage >&2; exit 2; }

caller="$(printf '%s' "$caller" | tr '[:upper:]' '[:lower:]')"
cfg '.callers[]' | grep -Fxq "$caller" || die "caller '$caller' is not authorized in $CONFIG."

max_level="$(cfg '.maxLevel')"
[[ "$(level_rank "$level")" -ge 0 ]] || die "level must be one of: ${LEVELS[*]}"
if [[ "$(level_rank "$level")" -gt "$(level_rank "$max_level")" ]]; then
    die "level '$level' exceeds the current Aldaris limit '$max_level'. Do this step yourself."
fi

model="$(cfg '.model')"
ollama_url="$(cfg '.ollamaUrl')"
context_length="$(cfg '.contextLength')"

curl -fsS --max-time 3 "$ollama_url/api/version" >/dev/null 2>&1 \
    || die "Ollama is not reachable at $ollama_url. Do this step yourself."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
input="$tmp_dir/input.txt"
: > "$input"
input_summary=()

for f in "${files[@]+"${files[@]}"}"; do
    if [[ "$f" == "-" ]]; then
        stdin_file="$tmp_dir/stdin.txt"
        cat > "$stdin_file"
        printf '===== STDIN =====\n' >> "$input"
        cat "$stdin_file" >> "$input"
        printf '\n===== END STDIN =====\n\n' >> "$input"
        input_summary+=("stdin ($(wc -c < "$stdin_file" | tr -d ' ') B)")
        continue
    fi
    [[ -f "$f" ]] || die "input file not found: $f"
    [[ "$(cd "$(dirname "$f")" && pwd -P)/" != *"/config-local/"* ]] || die "refusing secret-bearing path: $f"
    printf '===== FILE: %s =====\n' "$f" >> "$input"
    cat "$f" >> "$input"
    printf '\n===== END FILE: %s =====\n\n' "$f" >> "$input"
    input_summary+=("$f ($(wc -c < "$f" | tr -d ' ') B)")
done

system_prompt='You are Aldaris, a local helper that performs one bounded text task for a senior engineer.
Output only the requested result: no preamble, no closing remarks, no questions.
Do not invent facts that are not in the provided input.
If the task is ambiguous, beyond your confidence, or the input is insufficient, reply with exactly one line:
ALDARIS_DECLINE: <short reason>'

jq -n --arg model "$model" --arg system "$system_prompt" --arg task "$task" \
    --rawfile input "$input" --argjson ctx "$context_length" '
    {
        model: $model,
        stream: false,
        options: {temperature: 0, num_ctx: $ctx},
        messages: [
            {role: "system", content: $system},
            {role: "user", content: ("TASK:\n" + $task + (if $input == "" then "" else "\n\nINPUT:\n" + $input end))}
        ]
    }' > "$tmp_dir/request.json"

id="$(date '+%Y%m%d-%H%M%S')-$RANDOM"
started_at="$(date '+%Y-%m-%d %H:%M:%S')"
start_epoch="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"

if ! curl -fsS --max-time 900 "$ollama_url/api/chat" \
        -H 'Content-Type: application/json' -d @"$tmp_dir/request.json" > "$tmp_dir/response.json"; then
    die "Ollama request failed. Do this step yourself."
fi

end_epoch="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
duration="$(awk -v s="$start_epoch" -v e="$end_epoch" 'BEGIN { printf "%.1f", e - s }')"
response="$(jq -r '.message.content // ""' "$tmp_dir/response.json")"
prompt_tokens="$(jq -r '.prompt_eval_count // 0' "$tmp_dir/response.json")"
output_tokens="$(jq -r '.eval_count // 0' "$tmp_dir/response.json")"
declined=false
[[ "$response" == ALDARIS_DECLINE:* ]] && declined=true

jq -cn --arg id "$id" --arg caller "$caller" --arg level "$level" --arg maxLevel "$max_level" \
    --arg task "$task" --arg startedAt "$started_at" --arg model "$model" \
    --argjson durationSeconds "$duration" --argjson promptTokens "$prompt_tokens" \
    --argjson outputTokens "$output_tokens" --argjson declined "$declined" \
    --args '{type:"delegation", id:$id, caller:$caller, level:$level, maxLevel:$maxLevel,
        task:$task, inputs:$ARGS.positional, startedAt:$startedAt, model:$model,
        durationSeconds:$durationSeconds, promptTokens:$promptTokens,
        outputTokens:$outputTokens, declined:$declined}' \
    "${input_summary[@]+"${input_summary[@]}"}" >> "$LOG_FILE"

rule="════════════════════════════════════════════════════════════════════════"
caller_name="$(printf '%s' "${caller:0:1}" | tr '[:lower:]' '[:upper:]')${caller:1}"
echo "$rule"
echo "  ⚡ ALDARIS DELEGATION  ·  $caller_name → Aldaris"
echo "$rule"
echo "  id:        $id"
echo "  when:      $started_at"
echo "  level:     $level (current limit: $max_level)"
echo "  model:     $model"
if [[ ${#input_summary[@]} -gt 0 ]]; then
    echo "  inputs:    ${input_summary[0]}"
    for extra in "${input_summary[@]:1}"; do echo "             $extra"; done
else
    echo "  inputs:    none"
fi
echo "  asked:     $task"
echo "────────────────────────────── RESPONSE ─────────────────────────────────"
printf '%s\n' "$response"
echo "─────────────────────────────────────────────────────────────────────────"
echo "  duration:  ${duration}s  (prompt ${prompt_tokens} tok, output ${output_tokens} tok)"
if [[ "$declined" == true ]]; then
    echo "  status:    DECLINED by Aldaris — do this step yourself"
fi
echo "  verdict:   pending → aldaris-ask --verdict $id accepted|corrected|rejected"
echo "$rule"
