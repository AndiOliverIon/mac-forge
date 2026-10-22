# Handoff — QA

Apply with `common.md` and the station flow when the trigger contains `QA`. A QA handoff asks the
Reviewer (the Tester) to use the running application like a user and confirm that the outcome is what
the Coworker expects. It is not a code review: the Tester judges observed behavior, not source code or
builds.

QA is currently enabled on Hades only. On any other station, stop and tell Oliver.

## Place in the Workflow

- QA is the last step of a task: it starts only after the code-review cycle ended with the Coworker,
  the Reviewer, and Oliver in agreement. Oliver's QA trigger is that agreement.
- A `passed` verdict confirms the agreed outcome. Any other verdict reopens the work for the Coworker,
  the code Reviewer, and Oliver; QA itself never fixes anything.
- Oliver owns the environment: he builds and deploys the app, prepares a disposable snapshot database
  on VPS1, and gives the URL before the flow starts. Agents never build, start, restart, deploy, or
  restore anything for QA.

## Pairing and Files

- Default when Oliver names no Reviewer: Artanis tests. Any of Artanis, Argus, or Aegis may test when
  its session has a working browser or app-automation tool; Aldaris never tests.
- Before writing anything, the Tester confirms such a tool is available. If not, report that and stop.
- The pair is `qa-request-<coworker>.md` (Coworker) and `qa-report-<coworker>.md` (Tester). Both carry
  `Kind: qa`. Captured evidence goes only in the Tester-owned owner-only directory
  `qa-evidence-<coworker>/` in the same lane, fully replaced each cycle.
- The handoff ID uses the station flow's format with `qa` inserted before the coworker token.
- A completed result is a report with `Status: qa-complete`.
- QA has no autonomous loop; `team-work.sh` never runs QA handoffs.

## Tester Authority

- The URL Oliver gives is safe for QA by definition. On it, the Tester decides and performs whatever
  the cases require (creating, editing, deleting records, any operation the app offers) without
  asking, unless `Restrictions` limits it.
- If the app is unreachable or not functional at the URL, stop and report it to Oliver. Never test a
  substitute URL or environment.
- If a case needs the snapshot restored (for example, data was consumed by an earlier case), stop and
  ask Oliver for a restore, then continue the same handoff after he confirms it.
- The authorization covers only the listed URLs. It does not authorize running automated test suites
  (unit, Playwright, Cypress, or similar); `always/test-execution.md` still governs those. The Tester
  never edits repository, configuration, or application code.
- Login credentials in the request may be used for the run but never copied into the report or
  evidence.

## Coworker: Prepare for QA

Trigger: Oliver says **“Prep for `<Reviewer>` QA takeoff”**, **“Prep for QA takeoff”** (Artanis tests),
**“Hand off to `<Reviewer>` for QA”**, **“QA handoff to `<Reviewer>`”**, or an unambiguous equivalent.

The request must be self-sufficient: the Tester has none of the task's conversation, code, or review
context, only this file. Write it from the task you worked on with Oliver.

1. Resolve and verify the routed lane and canonical repository root. Create a lane only when the
   station flow permits it for this trigger. Confirm the Tester differs from yourself.
2. Take the URL and login from Oliver or the task context. If either is missing, ask Oliver; never
   guess or substitute one.
3. Write test cases that prove the agreed outcome: which page to open, what to do, and what must be
   observed. Cover the changed behavior and the acceptance criteria; leave steps out only where
   exploratory testing is intended.
4. Generate a new handoff ID and completely replace only `qa-request-<coworker>.md` using the
   structure below. Leave the report, evidence, and every other pair unchanged.
5. Tell Oliver the request path, handoff ID, Coworker, and Tester. Say it is ready.

### Required `qa-request-<coworker>.md` Structure

```md
# QA Request

- Kind: qa
- Status: ready-for-qa
- Station: hades
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Coworker: <Artanis|Argus|Aegis|Aldaris>
- Reviewer: <Artanis|Argus|Aegis>
- Repository: <canonical absolute path>
- Branch: <branch>
- App URL: <URL Oliver provided>
- Code review: <approved review handoff ID, or “none”>
- Task: <ticket/key/title, or “none”>

## Objective

<What the user must now be able to do, in plain terms.>

## Access

<Login page, account, password or where Oliver keeps it, role, and any app area to start from.>

## Preconditions

<State the snapshot must already have for the cases, or “none”.>

## Test Cases

### QA-<n> — <high|medium|low>: <title>

- Page: <where to go>
- Steps: <what to do; omit only for exploratory testing>
- Expected: <what must be observed>

## Restrictions

<Limits for this run, or “none”.>

## Out of Scope

<Areas not to test, or “none”.>
```

## Reviewer: Process QA Handoff

Trigger: Oliver says **“`<Reviewer>` QA takeoff”** (for example **“Artanis QA takeoff”**), **“Process
`<Coworker>`'s QA handoff”**, or an unambiguous equivalent, to the agent that will test.

1. Select the pair as `common.md` specifies, scanning only `qa-request-*.md`.
2. Complete the identity and safety checks and load applicable project instructions. No stack
   guidelines are needed. `Coworker` and `Reviewer` must be valid as in `review.md`, differ, and
   `Coworker` must match the filename. Otherwise report and stop.
3. Confirm the tool and that the app is reachable and functional at the URL before any case.
4. Execute every case. Record failures with exact reproduction steps, including data you created or
   changed, and evidence. Note issues outside the cases separately; never fold them into the verdict.
5. Completely replace only `qa-report-<coworker>.md` and that pair's evidence directory. Leave the
   request, every other pair, and repository files unchanged.
6. Tell Oliver the report path, handoff ID, verdict, case counts, and the Coworker and Tester names.

Verdict: `passed` when every case passed; `failed` when any case failed; `blocked` when no case could
run; `partial` when some cases are blocked or not run and none failed.

### Required `qa-report-<coworker>.md` Structure

```md
# QA Report

- Kind: qa
- Status: qa-complete
- Station: hades
- Lane: <station-flow lane value>
- Handoff ID: <copied exactly from the request>
- Tested: <ISO-8601 timestamp>
- Coworker: <copied exactly from the request>
- Reviewer: <the testing agent>
- Reviewer override: <Oliver-directed (request named <name>) — include only when applicable>
- Repository: <canonical absolute path>
- Branch: <copied exactly from the request>
- App URL: <copied exactly from the request>
- Tool: <browser or automation tool used>
- Verdict: <passed|failed|blocked|partial>

## Summary

<Concise assessment and case counts by result.>

## Results

### QA-<n> — <pass|fail|blocked|not-run>: <title>

- Observed: <what happened>
- Expected: <copied from the request>
- Reproduce: <exact steps and data used; required for fail>
- Evidence: <paths under qa-evidence-<coworker>/, or “none”>
- Console and network: <errors seen, or “none”>

## Observations Outside the Requested Cases

<Issues noticed but not requested, or “None”.>

## Questions for Oliver and the Coworker

<Decisions or missing context, or “None”.>
```

## Coworker: Process the QA Report

Trigger: Oliver says **“Process `<Reviewer>`'s QA report”** (for example **“Process Artanis's QA
report”**) or an unambiguous equivalent. Follow `common.md`, classifying every non-passing case as
`bug`, `wrong expectation`, `environment`, or `uncertain`. Analysis only; stop for Oliver, who decides
whether the work reopens.
