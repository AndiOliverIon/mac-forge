# Artanis–Argus Review Handoff — Common Protocol

This file applies only after the review-handoff router selects a station flow. Oliver remains the decision-maker.

## Roles and Decision Boundary

- Artanis is the coworker and implementation partner. Artanis prepares review requests and later evaluates Argus's findings.
- Argus is the independent reviewer. Argus reviews the actual repository state and writes findings; Argus does not implement changes as part of this protocol.
- Findings do not authorize implementation. After Artanis analyzes the findings, Oliver and Artanis decide together what to accept, reject, or change. Artanis must not proceed until Oliver explicitly confirms the next action.

## Lane Isolation

- The selected station flow defines the active lane and its exact paths.
- Each lane uses exactly two transporter names: `request.md` and `findings.md`. A file may be absent until its owner first writes it.
- Multiple lanes may operate concurrently, but they must never cross.
- While operating in one lane, never read, create, edit, clear, or replace transporter files in another lane.
- A handoff concerns exactly one repository. If the requested review spans multiple repositories, stop and ask Oliver to select one repository or authorize separate handoffs.

## File Ownership and Replacement

- Only Artanis writes `request.md`.
- Only Argus writes `findings.md`.
- Each writer completely replaces the contents of its own file for every new cycle. Never append findings or requests and never create per-task transporter files.
- Neither agent clears, edits, or replaces the other agent's file.
- Before reading or writing a transporter file, reject it if it is a symlink or is not a regular file. A missing owned file may be created only when the selected flow and active trigger permit it.
- The files represent only the latest state. Conversation and version-control history provide the longer-term record.

## Handoff Identity

The selected station flow defines the handoff-ID format and the exact `Station` and `Lane` values. Every new request must have a new handoff ID. Argus must copy it exactly into `findings.md`.

Before Argus reviews or Artanis analyzes findings, the agent must verify all of the following against the active session and selected lane:

- station;
- lane;
- canonical absolute repository path;
- handoff ID;
- review target.

A mismatch means the request or findings are stale, ambiguous, or belong to another task. Report the mismatch and stop without modifying repository or transporter files. The old `findings.md` intentionally remains while a new request awaits Argus; the handoff ID is the stale-response guard.

## Artanis: Prepare for Argus Takeoff

Trigger: Oliver says **“Prep for Argus takeoff”** or gives an unambiguous equivalent instruction.

Artanis must:

1. Route to and load the correct station flow.
2. Resolve and verify the active lane and canonical repository root. Create a lane only when the selected station flow explicitly permits Artanis to do so.
3. Inspect the actual repository, branch, working tree, and relevant task context.
4. Determine an exact review target, such as a commit, diff range, or explicitly bounded working-tree change. Do not use a vague target when a precise one is available.
5. Generate a new handoff ID using the selected station flow.
6. Completely replace the active lane's `request.md` using the required structure below.
7. Leave `findings.md` unchanged.
8. Tell Oliver that the request is ready and provide the request path and handoff ID. Do not claim that Argus has reviewed it.

If unrelated user changes exist, identify them and keep them outside the requested review scope unless Oliver explicitly includes them.

### Required `request.md` Structure

```md
# Review Request

- Status: ready-for-review
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
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

The request is a navigation aid, not evidence of correctness. Argus must verify it against the repository.

## Argus: Process Artanis's Review Handoff

Trigger: Oliver says **“Process Artanis's review handoff”**, **“Argus takeoff”**, or gives an unambiguous equivalent instruction.

Argus must:

1. Route to and load the correct station flow.
2. Resolve the active lane and read only that lane's `request.md`. Argus must not create a missing handoff root, lane, or request.
3. Verify the request metadata and repository against the active session.
4. Load the shared guideline router, review-mode stack guidelines, and applicable project instructions.
5. Independently inspect the actual review target. Do not rely on Artanis's implementation summary as proof.
6. Review only the defined scope unless an out-of-scope issue directly affects its correctness; label any such issue clearly.
7. Completely replace the active lane's `findings.md` using the required structure below, copying the handoff ID exactly.
8. Leave `request.md` and all repository files unchanged.
9. Tell Oliver that findings are ready and provide the findings path, handoff ID, and verdict.

Findings must be specific, evidence-backed, ordered by severity, and actionable. If there are no findings, state that explicitly and still record residual risks or verification limitations.

### Required `findings.md` Structure

```md
# Review Findings

- Status: review-complete
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <copied exactly from request.md>
- Reviewed: <ISO-8601 timestamp>
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

## Questions for Oliver and Artanis

<Decisions or missing context, or “None”.>
```

## Artanis: Process Argus's Findings

Trigger: Oliver says **“Process Argus's findings”** or gives an unambiguous equivalent instruction.

This trigger authorizes analysis only. Artanis must:

1. Route to and load the correct station flow.
2. Resolve the active lane and read both transporter files from that lane only.
3. Verify the station, lane, repository, review target, and handoff IDs match.
4. Independently inspect the relevant code and evidence for every finding using read-only investigation.
5. Classify each finding as `confirmed`, `partially valid`, `rejected`, or `uncertain`.
6. Immediately present Oliver with:
   - An overall assessment and Argus's verdict.
   - Each finding's classification.
   - Evidence supporting Artanis's assessment.
   - The recommended action and tradeoffs.
   - The decisions that Oliver and Artanis need to make together.
7. Stop for discussion and confirmation.

Artanis must not implement fixes, edit code or configuration, rewrite either transporter file, or perform other mutating actions merely because findings exist. Implementation starts only after Oliver explicitly confirms which actions to take.

## Subsequent Cycles

After Oliver and Artanis agree on actions, Artanis may implement only the confirmed scope. A later **“Prep for Argus takeoff”** starts the next review cycle by replacing `request.md` with a new handoff ID and an updated exact review target. Argus then replaces `findings.md` for that new ID.
