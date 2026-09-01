# Artanis–Argus Review Handoff Protocol

This protocol defines the persistent two-file review handoff between Artanis (Codex) and Argus (Claude). Oliver remains the decision-maker. The protocol is dormant unless Oliver invokes a handoff command or a clear natural-language equivalent.

## Roles and Decision Boundary

- Artanis is the coworker and implementation partner. Artanis prepares review requests and later evaluates Argus's findings.
- Argus is the independent reviewer. Argus reviews the actual repository state and writes findings; Argus does not implement changes as part of this protocol.
- Findings do not authorize implementation. After Artanis analyzes the findings, Oliver and Artanis decide together what to accept, reject, or change. Artanis must not proceed until Oliver explicitly confirms the next action.

## Environment Isolation

Resolve the active environment from the canonical current working path:

- A path at or below `/home/oliver/zeratul` belongs to `zeratul`.
- A path at or below `/home/oliver/raynor` belongs to `raynor`.
- If the path belongs to neither environment, or the environment cannot be determined safely, stop and ask Oliver which environment to use.

Each environment has exactly one active review lane. The two lanes may operate concurrently, but they must never cross. While working in one environment, never read or write the other environment's transporter files.

Use these fixed files:

### `zeratul`

- Artanis request: `/home/oliver/zeratul/.ai/review-handoff/request.md`
- Argus findings: `/home/oliver/zeratul/.ai/review-handoff/findings.md`

### `raynor`

- Artanis request: `/home/oliver/raynor/.ai/review-handoff/request.md`
- Argus findings: `/home/oliver/raynor/.ai/review-handoff/findings.md`

## File Ownership and Replacement

- Only Artanis writes `request.md`.
- Only Argus writes `findings.md`.
- Each writer completely replaces the contents of its own file for every new cycle. Never append findings or requests and never create per-task transporter files.
- Neither agent clears, edits, or replaces the other agent's file.
- The files represent only the latest state. Conversation and version-control history provide the longer-term record.

## Handoff Identity

Every new request must have a new handoff ID in this form:

`<environment>:<repository-name>:<ISO-8601 timestamp>`

Argus must copy the handoff ID exactly into `findings.md`. Before Argus reviews or Artanis analyzes findings, the agent must verify that the environment, repository, and handoff ID match the active request. A mismatch means the findings are stale or belong to another task: report the mismatch and stop without modifying code or transporter files.

The old `findings.md` intentionally remains in place while a new request awaits Argus. The handoff ID is the stale-response guard.

## Artanis: Prepare for Argus Takeoff

Trigger: Oliver says **“Prep for Argus takeoff”** or gives an unambiguous equivalent instruction.

Artanis must:

1. Resolve and verify the active environment.
2. Inspect the actual repository, branch, working tree, and relevant task context.
3. Determine an exact review target, such as a commit, diff range, or explicitly bounded working-tree change. Do not use a vague target when a precise one is available.
4. Generate a new handoff ID.
5. Completely replace the active environment's `request.md` using the required structure below.
6. Leave `findings.md` unchanged.
7. Tell Oliver that the request is ready and provide the request path and handoff ID. Do not claim that Argus has reviewed it.

If unrelated user changes exist, identify them and keep them outside the requested review scope unless Oliver explicitly includes them.

### Required `request.md` Structure

```md
# Review Request

- Status: ready-for-review
- Environment: <zeratul|raynor>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Repository: <absolute path>
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

The request is a navigation aid, not evidence of correctness. Argus must verify it against the repository.

## Argus: Process Artanis's Review Handoff

Trigger: Oliver says **“Process Artanis's review handoff”**, **“Argus takeoff”**, or gives an unambiguous equivalent instruction.

Argus must:

1. Resolve the active environment and read only that environment's `request.md`.
2. Verify the request's environment and repository against the current session.
3. Load the shared router, review-mode stack guidelines, and applicable project instructions.
4. Independently inspect the actual review target. Do not rely on Artanis's implementation summary as proof.
5. Review only the defined scope unless an out-of-scope issue directly affects its correctness; label any such issue clearly.
6. Completely replace the active environment's `findings.md` using the required structure below, copying the handoff ID exactly.
7. Leave `request.md` and all repository files unchanged.
8. Tell Oliver that findings are ready and provide the findings path, handoff ID, and verdict.

Findings must be specific, evidence-backed, ordered by severity, and actionable. If there are no findings, state that explicitly and still record residual risks or verification limitations.

### Required `findings.md` Structure

```md
# Review Findings

- Status: review-complete
- Environment: <zeratul|raynor>
- Handoff ID: <copied exactly from request.md>
- Reviewed: <ISO-8601 timestamp>
- Repository: <absolute path>
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

## Questions for Oliver and Artanis

<Decisions or missing context, or “None”.>
```

## Artanis: Process Argus's Findings

Trigger: Oliver says **“Process Argus's findings”** or gives an unambiguous equivalent instruction.

This trigger authorizes analysis only. Artanis must:

1. Resolve the active environment and read both transporter files from that environment only.
2. Verify the environment, repository, and handoff IDs match.
3. Independently inspect the relevant code and evidence for every finding using read-only investigation.
4. Classify each finding as `confirmed`, `partially valid`, `rejected`, or `uncertain`.
5. Immediately present Oliver with:
   - An overall assessment and Argus's verdict.
   - Each finding's classification.
   - Evidence supporting Artanis's assessment.
   - The recommended action and tradeoffs.
   - The decisions that Oliver and Artanis need to make together.
6. Stop for discussion and confirmation.

Artanis must not implement fixes, edit code or configuration, rewrite either transporter file, or perform other mutating actions merely because findings exist. Implementation starts only after Oliver explicitly confirms which actions to take.

## Subsequent Cycles

After Oliver and Artanis agree on actions, Artanis may implement only the confirmed scope. A later **“Prep for Argus takeoff”** starts the next review cycle by replacing `request.md` with a new handoff ID and an updated exact review target. Argus then replaces `findings.md` for that new ID.
