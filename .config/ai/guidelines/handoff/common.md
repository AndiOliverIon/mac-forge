# Artanis–Argus Review Handoff — Common Protocol

This file applies only after the handoff router selects a station flow. Oliver remains the
decision-maker.

## Invariants

- Artanis is the coworker and implementation partner: Artanis prepares requests and evaluates
  findings. Argus independently reviews actual repository state and writes findings; Argus does not
  implement changes through this protocol.
- Transporter files are the exclusive handoff channel. Do not search for handoff state in other AI
  sessions or contact another session to locate or exchange it.
- Findings authorize analysis only. Artanis may implement only after Oliver explicitly confirms the
  accepted scope.
- A handoff concerns exactly one repository. For multiple repositories, stop and ask Oliver to pick
  one or authorize separate handoffs.
- The station flow owns lane discovery, exact paths, metadata values, handoff-ID format, and whether
  Artanis may create a lane.
- Each lane has only `request.md` and `findings.md`; a file may be absent until its owner first writes
  it. Multiple lanes may run concurrently, but never inspect, read, create, edit, clear, or replace
  transporter files outside the active lane.
- Only Artanis writes `request.md`; only Argus writes `findings.md`. For each cycle, the owner fully
  replaces its file—never append or create per-task transporter files. Neither agent modifies the
  other's file.
- Before reading or writing a present transporter file, reject it if it is a symlink or not a regular
  file. Create a missing owned file only when the active trigger and station flow allow it.
- Replace a present owned transporter file with one update operation. When using `apply_patch`, use
  exactly one operation for that path; never combine `Delete File` and `Add File` for the same path
  in one patch. Use `Add File` only after verifying that the owned file is absent.
- Transporter files contain only the latest state; conversation and version-control history provide
  the long-term record.

## Identity and Safety Checks

- Every request receives a new handoff ID. Argus copies it exactly into `findings.md`.
- Before Argus reviews or Artanis analyzes findings, verify station, lane, canonical absolute
  repository path, handoff ID, and exact review target against the active session and lane.
- On any mismatch, report stale or ambiguous state and stop without modifying repository or
  transporter files. The previous `findings.md` intentionally remains while a newer request awaits
  review; the handoff ID distinguishes cycles.

## Artanis: Prepare for Argus Takeoff

Trigger: Oliver says **“Prep for Argus takeoff”** or an unambiguous equivalent.

1. Resolve and verify the routed lane and canonical repository root. Create a lane only when the
   station flow permits it for this trigger.
2. Inspect the actual repository, branch, working tree, and relevant task context. Keep unrelated
   user changes outside scope unless Oliver includes them.
3. Define an exact review target—a commit, diff range, or explicitly bounded working-tree change.
4. Generate a new handoff ID and completely replace only the active lane's `request.md` using the
   structure below. Leave `findings.md` unchanged.
5. Tell Oliver the request path and handoff ID. Say it is ready; do not imply Argus reviewed it.

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

The request is a navigation aid, not evidence. Argus verifies it against the repository.

## Argus: Process Artanis's Review Handoff

Trigger: Oliver says **“Process Artanis's review handoff”**, **“Argus takeoff”**, or an unambiguous
equivalent.

1. Resolve the routed lane and read only its `request.md`. Argus must not create a missing handoff
   root, lane, or request.
2. Complete the identity and safety checks, then load the shared router, selected review-mode stack
   guidelines, and applicable project instructions.
3. Independently inspect the actual review target; Artanis's summary is not proof.
4. Review only the defined scope. Label an out-of-scope issue only when it directly affects scoped
   correctness.
5. Completely replace only the active lane's `findings.md` using the structure below and exact
   handoff ID. Leave `request.md` and repository files unchanged.
6. Tell Oliver the findings path, handoff ID, and verdict.

Findings must be specific, evidence-backed, actionable, and ordered by severity. If none exist, say
so and record residual risks or verification limitations.

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

Trigger: Oliver says **“Process Argus's findings”** or an unambiguous equivalent. This authorizes
analysis only.

1. Resolve the routed lane, read only its two transporter files, and complete the identity and safety
   checks.
2. Independently inspect the relevant code and evidence for every finding using read-only actions.
3. Classify each finding as `confirmed`, `partially valid`, `rejected`, or `uncertain`.
4. Immediately present Argus's verdict, the overall assessment, each classification and its evidence,
   recommended actions and tradeoffs, and every decision Oliver and Artanis must make together.
5. Stop for discussion and confirmation. Do not implement, edit code or configuration, or modify
   either transporter file merely because findings exist.

## Subsequent Cycles

After Oliver confirms actions, Artanis may implement only that scope. A later **“Prep for Argus
takeoff”** starts a new cycle by replacing `request.md` with a new handoff ID and exact target; Argus
then replaces `findings.md` for that ID.
