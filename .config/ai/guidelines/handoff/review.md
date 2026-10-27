# Handoff — Code Review

Apply with `common.md` and the station flow when the trigger is a code-review handoff (no `QA`).

## Pairing and Files

- Default when Oliver names no Reviewer: Artanis is the Coworker and Argus is the Reviewer.
- The pair is `request-<coworker>.md` (Coworker) and `findings-<coworker>.md` (Reviewer). These files
  carry no `Kind` header.
- Do not write bare `request.md` or `findings.md`. If an in-flight legacy pair still uses those names
  and `request-artanis.md` is absent, treat it as Artanis's pair only. If both legacy and named
  Artanis files exist, stop and ask Oliver. A request without `Reviewer` means `Argus`.
- A completed result is a findings file with `Status: review-complete`.

## Coworker: Prepare for Review

Trigger: Oliver says **“Prep for Argus takeoff”** (default reviewer), **“Prep for `<Reviewer>`
takeoff”**, **“Hand off to `<Reviewer>` for review”**, or an unambiguous equivalent. The addressed
agent is the Coworker for that cycle; the named agent, or Argus when none is named, is the Reviewer.

1. Resolve and verify the routed lane and canonical repository root. Create a lane only when the
   station flow permits it for this trigger. Confirm the Reviewer differs from yourself.
2. Inspect the actual repository, branch, working tree, and relevant task context. Keep unrelated
   user changes outside scope unless Oliver includes them.
3. Define an exact review target—a commit, diff range, or explicitly bounded working-tree change.
4. Generate a new handoff ID and completely replace only this Coworker's `request-<coworker>.md`
   using the structure below. Set `Coworker` to your own identity and `Reviewer` to the designated
   reviewer. Leave that Coworker's `findings-<coworker>.md` and every other pair unchanged.
5. Tell Oliver the request path, handoff ID, Coworker, and designated Reviewer. Say it is ready; do
   not imply the Reviewer reviewed it.

### Required `request-<coworker>.md` Structure

```md
# Review Request

- Status: ready-for-review
- Automation: <team-loop — autonomous loops only>
- Loop ID: <coordinator loop ID — autonomous loops only>
- Cycle: <positive integer — autonomous loops only>
- Cycle limit: <positive integer — autonomous loops only>
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Coworker: <Artanis|Argus|Aegis|Aldaris>
- Reviewer: <Artanis|Argus|Aegis>
- Repository: <canonical absolute path>
- Branch: <branch>
- Review target: <commit, diff range, or bounded working-tree scope>
- Task: <ticket/key/title, or “none”>

## Objective and Acceptance Criteria

<What the work must accomplish and how correctness will be judged.>

## Implementation Summary

<What changed, why, and the important design decisions.>

## Review Scope

<Exact commits, files, or diff to inspect, including explicit exclusions.>

## Validation Performed

<Checks, formatting, builds, or tests run; include results and clearly state what was not run.>

## Known Risks and Open Questions

<Suspected weaknesses, uncertainties, or “none known”.>

## Requested Review Focus

<Specific areas where independent scrutiny is most valuable.>
```

The request is a navigation aid, not evidence. The Reviewer verifies it against the repository.
For an autonomous loop, `Status: awaiting-oliver` is also valid when the Coworker cannot safely
continue. Such a request must contain an `## Escalation` section with the exact decision required.

## Reviewer: Process Review Handoff

Trigger: Oliver says **“Process `<Coworker>`'s review handoff”**, **“`<Reviewer>` takeoff”** (for
example **“Argus takeoff”**), or an unambiguous equivalent, to the agent that will review.

1. Select the pair as `common.md` specifies, scanning only `request-*.md`.
2. Complete the identity and safety checks, then load the shared router, selected review-mode stack
   guidelines, and applicable project instructions. `Coworker` must be Artanis, Argus, Aegis,
   or Aldaris (Aldaris only where the station flow admits him); `Reviewer` must be Artanis, Argus,
   or Aegis; they must differ, and `Coworker` must match the filename. Otherwise report and stop.
3. Independently inspect the actual review target; the Coworker's summary is not proof.
4. Review only the defined scope. Label an out-of-scope issue only when it directly affects scoped
   correctness.
5. Completely replace only that pair's `findings-<coworker>.md` using the structure below, the exact
   handoff ID, and `Coworker` copied exactly. Set `Reviewer` to yourself. Add the override line when
   it applies. Leave the request, every other pair, and repository files unchanged.
6. Tell Oliver the findings path, handoff ID, verdict, and the Coworker and Reviewer names.

Findings must be specific, evidence-backed, actionable, and ordered by severity. If none exist, say
so and record residual risks or verification limitations.

### Required `findings-<coworker>.md` Structure

```md
# Review Findings

- Status: review-complete
- Automation: <team-loop — autonomous loops only>
- Loop ID: <copied exactly — autonomous loops only>
- Cycle: <copied exactly — autonomous loops only>
- Cycle limit: <copied exactly — autonomous loops only>
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <copied exactly from the request>
- Reviewed: <ISO-8601 timestamp>
- Coworker: <copied exactly from the request>
- Reviewer: <the reviewing agent>
- Reviewer override: <Oliver-directed (request named <name>) — include only when applicable>
- Repository: <canonical absolute path>
- Branch: <branch reviewed>
- Review target: <actual target reviewed>
- Verdict: <approved|changes-required|discussion-required>

## Review Summary

<Concise independent assessment.>

## Validation and Inspection Performed

<Diffs, code paths, checks, tests, or other evidence inspected; include limitations.>

## Findings

### <FINDING-ID> — <severity>: <title>

- Location: <file and line or precise area>
- Claim: <what is wrong>
- Evidence: <why the claim is supported>
- Impact: <why it matters>
- Recommendation: <specific correction or decision>

<Repeat for each finding, or state “No findings.”>

## Non-Blocking Observations

<Optional improvements that are not required for approval, or “None”.>

## Questions for Oliver and the Coworker

<Decisions or missing context, or “None”.>
```

## Coworker: Process the Reviewer's Findings

Trigger: Oliver says **“Process `<Reviewer>`'s findings”** (for example **“Process Argus's
findings”**) or an unambiguous equivalent. Follow `common.md`, classifying each finding as
`confirmed`, `partially valid`, `rejected`, or `uncertain`. Analysis only unless the prompt carries a
valid active autonomous team-loop ID and cycle; then follow the bounded behavior below.

## Autonomous Team Loop

Trigger: Oliver starts `team-work.sh --prompt <task>` or gives an equivalent instruction that names
`Automation: team-loop`, the exact loop ID, cycle, cycle limit, Coworker, Reviewer, repository, and
transporter paths. The initial task is Oliver's authorization boundary. Default participants are
Artanis as Coworker and Argus as Reviewer; the coordinator may name another explicit pairing.
This is an additional opt-in flow for code review only. Never infer it from an ordinary prep, takeoff,
findings, or review request; without valid loop metadata, use the manual protocol and keep Oliver in
every cycle.

- `team-work.sh` is a deterministic coordinator, not a participant or AI identity. It may launch or
  resume the two sessions named by Oliver, validate structured headers, and advance loop state; it
  never reviews code, evaluates findings, or resolves a disagreement. Only it invokes the separately
  bootstrapped real sessions; each participant acts only as the identity assigned to that runtime.
- Only `team-work.sh` writes `team-loop-<coworker>.json`, which contains control state and real
  runtime session IDs only. Participants must not modify it or use it as a substitute for the
  transporter pair.
- Only `team-work.sh` writes files under the lane's `transcripts/` directory. Each autonomous task
  receives one owner-only Markdown file with a concise task slug and UTC timestamp in its filename.
  It records Oliver's task and decisions, participant prompts and final responses, transporter
  snapshots, verdicts, pauses, and the terminal outcome. It does not preserve hidden reasoning or a
  raw tool-event stream. Participants never use it as an input or control channel and must not
  modify it.
- An autonomous request and its findings carry identical `Automation`, `Loop ID`, `Cycle`, and
  `Cycle limit` headers. Reject missing or mismatched loop metadata.

1. The Coworker may implement the initial task and, on later cycles, confirmed in-scope findings.
   After loading this handoff protocol, it must resolve development mode for the actual target files
   and load every selected stack and project instruction before editing. Preserve unrelated changes.
   Do not commit, push, deploy, run an unauthorized unit test, perform a destructive action, or
   expand scope merely because the loop is autonomous.
2. The Coworker classifies every finding as `confirmed`, `partially valid`, `rejected`, or
   `uncertain`. It implements confirmed in-scope corrections. A rejection or partial acceptance must
   be carried with evidence in the next request so the Reviewer can reconsider it.
3. The Reviewer remains independent, inspects actual repository state, and never implements. If it
   maintains a blocking finding after the Coworker's evidence-based challenge, it writes
   `Verdict: discussion-required` and states the exact disagreement for Oliver.
4. Either participant escalates an ambiguous business or architectural decision, scope expansion,
   destructive action, missing authority, or unsafe uncertainty. The Coworker uses
   `Status: awaiting-oliver`; the Reviewer uses `Verdict: discussion-required`. Do not manufacture
   agreement to keep the loop moving. The running coordinator waits for Oliver's plain-text decision
   in the same terminal and passes it to the existing Coworker session; Oliver does not invoke a
   second command to resume the loop. The reserved decision `/stop` ends the loop without approval,
   records `stopped-by-oliver`, and permits a later invocation to start a new task.
5. `Verdict: changes-required` returns control to the same real Coworker session for the next cycle.
   A new request gets a new handoff ID and the incremented cycle. `Verdict: approved` ends the loop
   and returns the final request and findings to Oliver; it is technical approval within scope, not
   Oliver's approval to commit, push, deploy, or publish.
6. The coordinator waits interactively at `awaiting-oliver`, `discussion-required`, an integrity
   violation, or the cycle limit. It parses only structured state and never decides whether a finding
   is correct. Runtime failure stops the loop fail-closed. Approval or Oliver's explicit `/stop`
   ends that loop, so the next invocation starts a new task.
7. The coordinator appends every workflow exchange to the task's transcript and records its absolute
   path in coordinator state. Transcript failure is workflow failure; an agent modification of the
   transcript is an integrity violation.
