# Aldaris Delegation

Aldaris is a local, non-accountable text helper (Ollama `qwen3-coder:30b` on Hades), not a team
identity. It never acts as Coworker or Reviewer and never edits files. The delegating identity stays
fully accountable for every result it uses.

## Who and when

- Delegation is allowed by default. When Oliver's prompt says not to use Aldaris, do not delegate
  any step of that task until Oliver allows it again.
- Only the callers listed in `~/mac-forge/configs/aldaris.json` may delegate (currently Artanis,
  Argus, and Aegis). The same file sets `maxLevel`; only Oliver changes it.
- Delegate a step only when you have high confidence Aldaris will handle it correctly and checking
  its answer costs less than doing the step yourself. When in doubt, do it yourself.
- Good fits: summarizing or extracting from large inputs, reformatting, sorting, boilerplate text,
  one-line descriptions. Never delegate reviews, findings, security or destructive decisions,
  database changes, secrets or `config-local/` content, or anything requiring repository rules.
- Classify every step honestly as `trivial`, `standard`, `moderate`, or `high`. The script refuses
  levels above `maxLevel`; never downgrade a level to get past the limit.

## How

Run `~/mac-forge/scripts/aldaris-ask.sh --caller <you> --level <level> --task "<instruction>"
[--file <path> ...]` (`--file -` reads piped stdin). Give it a precise, self-contained instruction.
If the script fails, Ollama is offline, or Aldaris replies `ALDARIS_DECLINE`, do the step yourself
and continue the task without stopping, retrying at a higher level, or starting Ollama; mention the
fallback in one line.

## Visibility and verdict

- Tool output may be hidden from Oliver. For every delegation, reproduce in your reply a clearly
  marked `⚡ ALDARIS DELEGATION` block containing: id, when, level, what you asked, Aldaris's response
  (verbatim, or trimmed with the omission stated), and duration.
- Verify the response before using it, then record the outcome with
  `~/mac-forge/scripts/aldaris-ask.sh --verdict <id> accepted|corrected|rejected [--note "<why>"]` and
  state that verdict in the same block. `corrected` means you had to fix it before use.
- Oliver reviews `aldaris-ask --stats` to decide whether to raise `maxLevel` or add callers.
