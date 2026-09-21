# Review Handoff — Common Protocol

This file applies only after the handoff router selects a station flow. Oliver remains the
decision-maker.

## Roles and Defaults

- Every handoff has exactly two participants: the **Coworker** (author who prepares the request and
  later evaluates findings) and the **Reviewer** (independent reviewer who writes findings). Any of
  Artanis, Karax, Argus, or Aegis may hold either role for a handoff.
- Recommended defaults, used whenever Oliver names no reviewer: Artanis or Karax is the Coworker and
  Argus is the Reviewer. Aegis assists with bounded, lower-complexity tasks by default.
- A role switch happens only when Oliver explicitly asks for it (for example "Aegis, hand off to
  Karax for review"). Never infer it, never carry it to another cycle, and never let an agent
  self-assign a role. A cycle with no named reviewer reverts to the defaults.
- The Reviewer must not be the Coworker, and must not have implemented the review target, as known
  from its own session or evident from the repository. If either holds, stop and ask Oliver.
- Neither participant learns the other's role from another AI session: the transporter files carry
  both names, and each agent's own identity comes from its bootstrap.

## Invariants

- Argus or any other Reviewer independently reviews actual repository state and writes findings; a
  Reviewer does not implement changes through this protocol.
- Transporter files are the exclusive handoff channel. Do not search for handoff state in other AI
  sessions or contact another session to locate or exchange it.
- Findings authorize analysis only. The Coworker may implement only after Oliver explicitly confirms
  the accepted scope.
- A handoff concerns exactly one repository. For multiple repositories, stop and ask Oliver to pick
  one or authorize separate handoffs.
- The station flow owns lane discovery, exact paths, metadata values, handoff-ID format, and whether
  the Coworker may create a lane. A handoff never crosses lanes: both participants act inside the same
  lane, and a lane's own concurrency and isolation rules are unchanged by role switching.
- Each Coworker has a distinct transporter pair in the active lane: `request-<coworker>.md` and
  `findings-<coworker>.md`, with the Coworker identity in lowercase (`artanis`, `karax`, `argus`,
  `aegis`). A file may be absent until its owner first writes it. Different Coworkers' jobs must never
  share or overwrite each other's files.
- Multiple lanes may run concurrently, and several pairs in one lane may be active at once, but never
  inspect, read, create, edit, clear, or replace transporter files outside the active lane or another
  job's pair, except for the header scan below.
- Only the Coworker writes `request-<coworker>.md`; only that pair's designated Reviewer writes
  `findings-<coworker>.md`. For each cycle, the owner fully replaces its file—never append or create
  per-task transporter files. Neither agent modifies the other's file. Both files name the Coworker
  and the Reviewer, and the Coworker name must match the filename.
- Before reading or writing a present transporter file, reject it if it is a symlink or not a regular
  file. Create a missing owned file only when the active trigger and station flow allow it.
- Replace a present owned transporter file with one update operation. When using `apply_patch`, use
  exactly one operation for that path; never combine `Delete File` and `Add File` for the same path
  in one patch. Use `Add File` only after verifying that the owned file is absent.
- Transporter files contain only the latest state; conversation and version-control history provide
  the long-term record.

## Identity and Safety Checks

- Every request receives a new handoff ID. The Reviewer copies it exactly into the matching
  `findings-<coworker>.md`.
- Before reviewing or analyzing findings, verify station, lane, Coworker, Reviewer, transporter
  filenames, canonical absolute repository path, handoff ID, and exact review target against the
  active session and lane. The acting agent must equal `Coworker` when preparing or analyzing
  findings, and `Reviewer` when reviewing, unless the override below applies.
- On any mismatch, report stale or ambiguous state and stop without modifying repository or
  transporter files. The previous `findings-<coworker>.md` intentionally remains while a newer request
  in the same pair awaits review; the handoff ID distinguishes cycles. Other pairs are different jobs
  and must be left untouched.
- Do not write bare `request.md` or `findings.md`. If an in-flight legacy pair still uses those names
  and `request-artanis.md` is absent, treat it as Artanis's pair only. If both legacy and named
  Artanis files exist, stop and ask Oliver. A request without `Reviewer` means `Argus`.

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
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Coworker: <Artanis|Karax|Argus|Aegis>
- Reviewer: <Artanis|Karax|Argus|Aegis>
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

## Reviewer: Process Review Handoff

Trigger: Oliver says **“Process `<Coworker>`'s review handoff”**, **“`<Reviewer>` takeoff”** (for
example **“Argus takeoff”**), or an unambiguous equivalent, to the agent that will review.

1. Resolve the routed lane and select the pair:
   - **Author named** (“Process Aegis's review handoff”): use `request-<coworker>.md` for that author.
     Naming the author to an agent that is not the request's `Reviewer` is Oliver's explicit
     override: proceed and record it in the findings.
   - **Bare takeoff** (“Karax takeoff”): scan only the header lines (`Status`, `Handoff ID`,
     `Coworker`, `Reviewer`) of each `request-*.md` in the lane. A request is pending for you when its
     `Reviewer` is you and no `review-complete` findings file in its pair has the same handoff ID.
     Exactly one pending request selects the pair; several means ask Oliver which job to review; none
     means report the pending requests that name other reviewers and stop. Read no other content of
     any other pair.

   Never create a missing handoff root, lane, or request.
2. Complete the identity and safety checks, then load the shared router, selected review-mode stack
   guidelines, and applicable project instructions. `Coworker` and `Reviewer` must each be one of the
   four identities and differ, and `Coworker` must match the filename. Otherwise report and stop.
3. Independently inspect the actual review target; the Coworker's summary is not proof.
4. Review only the defined scope. Label an out-of-scope issue only when it directly affects scoped
   correctness.
5. Completely replace only that pair's `findings-<coworker>.md` using the structure below, the exact
   handoff ID, and `Coworker` copied exactly. Set `Reviewer` to yourself. When you were not the
   request's `Reviewer`, add `Reviewer override: Oliver-directed (request named <name>)`. Leave the
   request, every other pair, and repository files unchanged.
6. Tell Oliver the findings path, handoff ID, verdict, and the Coworker and Reviewer names.

Findings must be specific, evidence-backed, actionable, and ordered by severity. If none exist, say
so and record residual risks or verification limitations.

### Required `findings-<coworker>.md` Structure

```md
# Review Findings

- Status: review-complete
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
findings”**) or an unambiguous equivalent. This authorizes analysis only. The addressed agent reads
only its own pair; a named Reviewer must match `Reviewer` in the findings.

1. Resolve the routed lane, read only that Coworker's two transporter files, and complete the
   identity and safety checks. Confirm `Coworker` and `Reviewer` in both files agree and that the
   findings' `Coworker` matches the filenames.
2. Independently inspect the relevant code and evidence for every finding using read-only actions.
3. Classify each finding as `confirmed`, `partially valid`, `rejected`, or `uncertain`.
4. Immediately present the Reviewer's verdict, the overall assessment, each classification and its
   evidence, recommended actions and tradeoffs, and every decision Oliver and the Coworker must make
   together. State both names.
5. Stop for discussion and confirmation. Do not implement, edit code or configuration, or modify
   either transporter file merely because findings exist.

## Subsequent Cycles

After Oliver confirms actions, the Coworker may implement only that scope. A later prep trigger starts
a new cycle by replacing that Coworker's `request-<coworker>.md` with a new handoff ID, exact target,
`Coworker`, and `Reviewer` (Argus unless Oliver names another); the Reviewer then replaces that same
pair's `findings-<coworker>.md`. Every other pair is a separate job.
