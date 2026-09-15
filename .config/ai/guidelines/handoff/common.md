# Artanis–Argus Review Handoff — Common Protocol

This file applies only after the handoff router selects a station flow. Oliver remains the
decision-maker.

## Invariants

- The coworker is Artanis or Karax: that agent prepares requests and evaluates findings. Argus
  independently reviews actual repository state and writes findings; Argus does not implement changes
  through this protocol.
- Transporter files are the exclusive handoff channel. Do not search for handoff state in other AI
  sessions or contact another session to locate or exchange it.
- Findings authorize analysis only. The coworker may implement only after Oliver explicitly confirms
  the accepted scope.
- A handoff concerns exactly one repository. For multiple repositories, stop and ask Oliver to pick
  one or authorize separate handoffs.
- The station flow owns lane discovery, exact paths, metadata values, handoff-ID format, and whether
  the coworker may create a lane.
- Each coworker has a distinct transporter pair in the active lane: `request-<coworker>.md` and
  `findings-<coworker>.md`, with the coworker identity in lowercase (`request-artanis.md`,
  `request-karax.md`). A file may be absent until its owner first writes it. Artanis's and Karax's
  jobs must never share or overwrite each other's files.
- Multiple lanes may run concurrently, and both coworker pairs in one lane may be active at once,
  but never inspect, read, create, edit, clear, or replace transporter files outside the active lane
  or the other coworker's pair.
- Only the active coworker writes that coworker's `request-<coworker>.md`; only Argus writes that
  same pair's `findings-<coworker>.md`. For each cycle, the owner fully replaces its file—never
  append or create per-task transporter files. Neither agent modifies the other's file. The request
  must name the coworker as `Artanis` or `Karax`, and that name must match the filename, so Argus
  always knows who pushed the review.
- Before reading or writing a present transporter file, reject it if it is a symlink or not a regular
  file. Create a missing owned file only when the active trigger and station flow allow it.
- Replace a present owned transporter file with one update operation. When using `apply_patch`, use
  exactly one operation for that path; never combine `Delete File` and `Add File` for the same path
  in one patch. Use `Add File` only after verifying that the owned file is absent.
- Transporter files contain only the latest state; conversation and version-control history provide
  the long-term record.

## Identity and Safety Checks

- Every request receives a new handoff ID. Argus copies it exactly into the matching
  `findings-<coworker>.md`.
- Before Argus reviews or the coworker analyzes findings, verify station, lane, coworker, transporter
  filenames, canonical absolute repository path, handoff ID, and exact review target against the
  active session and lane.
- On any mismatch, report stale or ambiguous state and stop without modifying repository or
  transporter files. The previous `findings-<coworker>.md` for that coworker intentionally remains
  while a newer request in the same pair awaits review; the handoff ID distinguishes cycles. The
  other coworker's pair is a different job and must be left untouched.
- Do not write bare `request.md` or `findings.md`. If an in-flight legacy pair still uses those names
  and `request-artanis.md` is absent, treat it as Artanis's pair only. If both legacy and named
  Artanis files exist, stop and ask Oliver.

## Coworker: Prepare for Argus Takeoff

Trigger: Oliver says **“Prep for Argus takeoff”** or an unambiguous equivalent. Artanis or Karax
executes this trigger as the coworker for that cycle.

1. Resolve and verify the routed lane and canonical repository root. Create a lane only when the
   station flow permits it for this trigger.
2. Inspect the actual repository, branch, working tree, and relevant task context. Keep unrelated
   user changes outside scope unless Oliver includes them.
3. Define an exact review target—a commit, diff range, or explicitly bounded working-tree change.
4. Generate a new handoff ID and completely replace only this coworker's `request-<coworker>.md`
   using the structure below. Set `Coworker` to the preparing agent's own identity, `Artanis` or
   `Karax`. Leave that coworker's `findings-<coworker>.md` and the other coworker's pair unchanged.
5. Tell Oliver the request path, handoff ID, and coworker name. Say it is ready; do not imply Argus
   reviewed it.

### Required `request.md` Structure

```md
# Review Request

- Status: ready-for-review
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Coworker: <Artanis|Karax>
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

## Argus: Process Review Handoff

Trigger: Oliver says **“Process Artanis's review handoff”**, **“Process Karax's review handoff”**,
**“Argus takeoff”**, or an unambiguous equivalent.

1. Resolve the routed lane. Select the coworker pair from Oliver's named trigger, or from `Coworker`
   if already known. If Oliver said **“Argus takeoff”** without naming a coworker, use the sole
   ready `request-<coworker>.md` in that lane; if more than one coworker has a ready request, stop
   and ask which job to review. Argus must not create a missing handoff root, lane, or request, and
   must not read the other coworker's pair except to detect that ambiguity.
2. Complete the identity and safety checks, then load the shared router, selected review-mode stack
   guidelines, and applicable project instructions. Read `Coworker` from the selected request. On
   Hades, Raynor, and Zeratul it must be `Artanis` or `Karax` and must match the filename. If it is
   missing, invalid, or does not match the named trigger when Oliver named a coworker, report the
   mismatch and stop.
3. Independently inspect the actual review target; the coworker's summary is not proof.
4. Review only the defined scope. Label an out-of-scope issue only when it directly affects scoped
   correctness.
5. Completely replace only that coworker's `findings-<coworker>.md` using the structure below, the
   exact handoff ID, and the request's `Coworker` value copied exactly. Leave that request, the other
   coworker's pair, and repository files unchanged.
6. Tell Oliver the findings path, handoff ID, verdict, and which coworker requested the review.

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
- Coworker: <copied exactly from request.md>
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

## Questions for Oliver and the coworker

<Decisions or missing context, or “None”.>
```

## Coworker: Process Argus's Findings

Trigger: Oliver says **“Process Argus's findings”** or an unambiguous equivalent. This authorizes
analysis only. The named `Coworker` evaluates that coworker's findings unless Oliver names the other
coworker. If both pairs have findings and Oliver did not name a coworker, stop and ask.

1. Resolve the routed lane, read only that coworker's two transporter files, and complete the
   identity and safety checks. Confirm `Coworker` in both files matches the filenames, and that it is
   `Artanis` or `Karax`.
2. Independently inspect the relevant code and evidence for every finding using read-only actions.
3. Classify each finding as `confirmed`, `partially valid`, `rejected`, or `uncertain`.
4. Immediately present Argus's verdict, the overall assessment, each classification and its evidence,
   recommended actions and tradeoffs, and every decision Oliver and the named coworker must make
   together. State that coworker name.
5. Stop for discussion and confirmation. Do not implement, edit code or configuration, or modify
   either transporter file merely because findings exist.

## Subsequent Cycles

After Oliver confirms actions, the named coworker may implement only that scope. A later **“Prep for
Argus takeoff”** starts a new cycle by replacing that coworker's `request-<coworker>.md` with a new
handoff ID, exact target, and `Coworker` identity; Argus then replaces that same pair's
`findings-<coworker>.md`. The other coworker's pair is a separate job.
