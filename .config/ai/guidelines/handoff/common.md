# Handoff — Common Protocol

This file applies only after the handoff router selects a station flow and exactly one handoff kind:
`review.md` for code review or `qa.md` for QA (hands-on testing of a running application). Oliver
remains the decision-maker.

## Roles and Defaults

- Every handoff has exactly two participants: the **Coworker** (author who prepares the request and
  later evaluates the result) and the **Reviewer** (independent participant who writes the result:
  code-review findings or a QA report). Any of Artanis, Argus, or Aegis may hold either role for a
  handoff; the kind file may restrict who can act as Reviewer.
- Aldaris may hold only the Coworker role, only in manual handoffs on a station whose flow admits
  him (currently Hades), and only for work Oliver assigned to him. He never reviews or tests and
  never takes part in an autonomous team loop. Apart from reviewing or testing his handoffs and
  writing their results, Artanis, Argus, and Aegis do not interact with Aldaris.
- Default pairings, used whenever Oliver names no Reviewer, are defined by the kind file. Aegis
  assists with bounded, lower-complexity tasks by default.
- A role switch happens only when Oliver explicitly asks for it (for example "Aegis, hand off to
  Artanis for review"). Never infer it, never carry it to another cycle, and never let an agent
  self-assign a role. A cycle with no named Reviewer reverts to the kind's default.
- The Reviewer must not be the Coworker, and must not have implemented the target, as known from its
  own session or evident from the repository. If either holds, stop and ask Oliver.
- Neither participant learns the other's role from another AI session: the transporter files carry
  both names, and each agent's own identity comes from its bootstrap.

## Invariants

- The Reviewer independently inspects the actual target and writes the result; a Reviewer does not
  implement changes through this protocol.
- Transporter files are the exclusive channel for substantive handoff content. Do not search for
  handoff state in other AI sessions or contact another session to locate or exchange it.
- A result authorizes analysis only. The Coworker may implement only after Oliver explicitly
  confirms the accepted scope, except where the kind file defines an autonomous loop that allows it.
- Neither participant may launch, invoke, spawn, or simulate its counterpart.
- A handoff concerns exactly one repository. For multiple repositories, stop and ask Oliver to pick
  one or authorize separate handoffs.
- The station flow owns lane discovery, exact paths, metadata values, handoff-ID format, and whether
  the Coworker may create a lane. A handoff never crosses lanes: both participants act inside the same
  lane, and a lane's own concurrency and isolation rules are unchanged by role switching.
- Each Coworker has a distinct transporter pair per handoff kind in the active lane, named by the
  kind file, with the Coworker identity in lowercase (`artanis`, `argus`, `aegis`, `aldaris`). A file
  may be absent until its owner first writes it. Different Coworkers' or kinds' jobs must never share
  or overwrite each other's files.
- Multiple lanes may run concurrently, and several pairs in one lane may be active at once, but never
  inspect, read, create, edit, clear, or replace transporter files outside the active lane or another
  job's pair, except for the header scan below.
- Only the Coworker writes the pair's request file; only that pair's designated Reviewer writes the
  pair's result file. For each cycle, the owner fully replaces its file—never append or create
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

- Every request receives a new handoff ID. The Reviewer copies it exactly into the matching result.
- The handoff kind comes from Oliver's trigger, never from file contents. QA files carry
  `Kind: qa`; code-review files carry no `Kind` header. A file whose kind differs from the trigger is a
  mismatch.
- Before reviewing, testing, or analyzing a result, verify station, lane, kind, Coworker, Reviewer,
  transporter filenames, canonical absolute repository path, handoff ID, and exact target against the
  active session and lane. The acting agent must equal `Coworker` when preparing or analyzing a
  result, and `Reviewer` when reviewing or testing, unless the override below applies or the kind
  file names another analyst.
- On any mismatch, report stale or ambiguous state and stop without modifying repository or
  transporter files. The previous result file intentionally remains while a newer request in the same
  pair awaits the Reviewer; the handoff ID distinguishes cycles. Other pairs are different jobs and
  must be left untouched.

## Reviewer: Select the Pair

1. **Author named** (“Process Aegis's review handoff”, “Process Argus's QA handoff”): use that
   author's request file of the trigger's kind. Naming the author to an agent that is not the
   request's `Reviewer` is Oliver's explicit override: proceed and record
   `Reviewer override: Oliver-directed (request named <name>)` in the result.
2. **Bare takeoff** (“Artanis takeoff”, “Artanis QA takeoff”): scan only the header lines (`Status`,
   `Handoff ID`, `Coworker`, `Reviewer`) of each request file of the trigger's kind in the lane. A
   request is pending for you when its `Reviewer` is you and no completed result in its pair has the
   same handoff ID. Exactly one pending request selects the pair; several means ask Oliver which job
   to take; none means report the pending requests that name other Reviewers, and any pending request
   of the other kind that names you, then stop. Read no other content of any other pair.

Never create a missing handoff root, lane, or request.

## Coworker: Process the Result

The trigger authorizes analysis only, except inside an autonomous loop defined by the kind file. The
addressed agent reads only its own pair of the trigger's kind; a named Reviewer must match `Reviewer`
in the result.

1. Resolve the routed lane, read only that Coworker's two transporter files of that kind, and complete
   the identity and safety checks. Confirm `Coworker` and `Reviewer` in both files agree and that the
   result's `Coworker` matches the filenames.
2. Independently inspect the relevant code and evidence for every item using read-only actions.
3. Classify each item as the kind file specifies.
4. Immediately present the Reviewer's verdict, the overall assessment, each classification and its
   evidence, recommended actions and tradeoffs, and every decision Oliver and the Coworker must make
   together. State both names.
5. For a manual handoff, stop for discussion and confirmation. Do not implement, edit code or
   configuration, or modify either transporter file merely because a result exists.

## Subsequent Cycles

After Oliver confirms actions, the Coworker may implement only that scope. A later prep trigger starts
a new cycle by replacing that Coworker's request file of that kind with a new handoff ID, exact target,
`Coworker`, and `Reviewer` (the kind's default unless Oliver names another); the Reviewer then replaces
that same pair's result file. Every other pair is a separate job.
