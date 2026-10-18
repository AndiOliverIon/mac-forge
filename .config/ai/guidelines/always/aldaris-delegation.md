# Aldaris Delegation

Aldaris is the local junior helper on Hades, not an independent reviewer or a replacement for the
accountable coworker. `aldaris-ask` performs bounded text tasks. The separate `aldaris` Qwen Code
launcher supports Oliver's manually supervised coding assignments.

## Oliver's switch

- At the start of each substantive task, check `~/mac-forge/scripts/aldaris-junior.sh status`.
  Recheck with its `check` command immediately before every invocation or retry. Missing or invalid
  state means OFF. The ignored `config-local/aldaris-junior.state` file is authoritative.
- Only Oliver turns delegation ON or OFF with `junior on` and `junior off`. Never enable it yourself,
  edit its state to bypass OFF, or treat an earlier ON observation as permanent authorization.
- OFF means work solo without Aldaris: no text calls, coding calls, direct model API requests, or
  background dispatch. Do not work around OFF through the manual launcher, another CLI, or a model
  server. Do not consume a result returned after delegation was disabled; stop retries and take over.
- The switch governs assistant delegation. It does not terminate Oliver's manual Aldaris sessions,
  unload his model, or change his configured context. Switching OFF blocks new dispatches; an already
  submitted inference may finish, but its result must not be used by assistants.

## Use the junior when ON

- Actively look for independent, bounded subtasks during planning and when the task grows. Delegate
  suitable work within the current ceiling when its result will be useful and review costs are
  reasonable. Do not skip merely because doing it yourself is familiar or slightly faster.
- Do not manufacture busywork or delegate the entire task simply to register an invocation. When ON
  but no useful eligible subtask exists, give one concise reason in the final response.
- Authorized callers and `maxLevel` live in `~/mac-forge/configs/aldaris/config.json`; only Oliver
  changes the ceiling. Rate steps honestly as `trivial`, `standard`, `moderate`, or `high`. Never
  downgrade a task to pass the limit. A successful manual experiment does not raise this ceiling.
- Current automatic eligibility is the text interface: summarizing, extracting, reformatting,
  sorting, boilerplate, and one-line descriptions from supplied non-secret excerpts. Never delegate
  reviews, findings, security or destructive decisions, database changes, secrets, or work requiring
  repository rules through it. Automated code editing requires the separate isolated coding-job
  infrastructure and Oliver-approved capability scope; the manual launcher is not that infrastructure.
- Run independent delegated work in the background when useful, continue your own work, and collect
  its result before finishing the parent task. Keep at most one assistant Aldaris request in flight
  and avoid starting work that would compete with Oliver's manual baseline evaluation.

## Visible dispatch and outcome

- Before every invocation, tell Oliver in commentary that you are engaging Aldaris, what bounded
  task he receives, and its complexity. Announce retries and returns for correction too. Tool output
  alone is insufficient. Never hide an invocation behind a final summary.
- Use `~/mac-forge/scripts/aldaris-ask.sh` (options in `--help`). Prefer a tested template and a schema
  for parsed output; send excerpts rather than whole files. If the service is offline, the call fails,
  or Aldaris declines, say so briefly and continue yourself. Do not automatically start or reload the
  model from this text-delegation interface.
- Assess usability before incorporating a result; you remain accountable. Return a narrow,
  correctable issue once when worthwhile, otherwise reject it and take over. Never loop indefinitely.
  Record accepted, corrected, or rejected outcomes with `--verdict`; use `--note` for the reason.
- Reproduce every call in the final reply as a `⚡ ALDARIS DELEGATION` block: id, when, level, request,
  response (trimmed only with the omission stated), duration, and outcome. Include an invocation
  count so Oliver can see how often Aldaris was engaged. List used ids in review requests.
