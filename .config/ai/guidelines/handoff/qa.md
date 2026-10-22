# Handoff — QA

Apply with `common.md` and the station flow when the trigger contains `QA`. A QA handoff asks the
Reviewer (the Tester) to use the running application like a user and report what happens. It is not
a code review: the Tester judges observed behavior, not source code.

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

## Safety Boundary

- The QA trigger authorizes interactive use of the listed URLs only, within the request's
  `Allowed Actions`. It does not authorize running automated test suites (unit, Playwright, Cypress,
  or similar); `always/test-execution.md` still governs those.
- Data defaults to read-only: create or change data only where `Allowed Actions` permits it. Never
  perform destructive or irreversible actions, real outbound effects (emails, payments, third-party
  calls), or production use, unless the request records Oliver's explicit approval for this handoff.
- Credentials are referenced by name and storage location only. Never write secrets into transporter
  files or evidence.
- The Tester never edits repository, configuration, or application code, and never restarts or
  redeploys the application unless the request says how and allows it.
- If the app is unreachable, or the observed build differs from `Build under test`, report `blocked`;
  never test a substitute. A case that would cross the boundary is `blocked`, not attempted.

## Coworker: Prepare for QA

Trigger: Oliver says **“Prep for `<Reviewer>` QA takeoff”**, **“Prep for QA takeoff”** (Artanis tests),
**“Hand off to `<Reviewer>` for QA”**, or an unambiguous equivalent.

1. Resolve and verify the routed lane and canonical repository root. Create a lane only when the
   station flow permits it for this trigger. Confirm the Tester differs from yourself.
2. Confirm the build that must be running and the URLs where it is reachable. If unknown, ask Oliver.
3. Write test cases from the task's acceptance criteria and the changed behavior. Leave steps out
   where exploratory testing is intended.
4. Generate a new handoff ID and completely replace only `qa-request-<coworker>.md` using the
   structure below. Leave the report, evidence, and every other pair unchanged.
5. Tell Oliver the request path, handoff ID, Coworker, and Tester. Say it is ready.

### Required `qa-request-<coworker>.md` Structure

```md
# QA Request

- Kind: qa
- Status: ready-for-qa
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <exact ID>
- Created: <ISO-8601 timestamp>
- Coworker: <Artanis|Argus|Aegis|Aldaris>
- Reviewer: <Artanis|Argus|Aegis>
- Repository: <canonical absolute path>
- Branch: <branch>
- Build under test: <commit or build identifier the app must be running>
- App URL: <one or more URLs; local or dev unless Oliver approved otherwise>
- Task: <ticket/key/title, or “none”>

## Objective

<What the feature must do for the user.>

## Environment and Access

<How the app is served, how to see its build, accounts and roles by name, where credentials live.>

## Preconditions and Test Data

<Required state, seed data, or “none”.>

## Test Cases

### QA-<n> — <high|medium|low>: <title>

- Goal: <behavior to verify>
- Steps: <optional exact steps; omit for exploratory testing>
- Expected: <observable expected result>

## Allowed Actions

- Data: <read-only|may create|may create and modify> <scope>
- Outbound effects: <none, or exactly what is allowed>
- Other: <restarts, file uploads, approvals by Oliver, or “none”>

## Out of Scope

<Areas not to test, or “none”.>

## Evidence Expected

<Screenshots, console output, network failures, or other captures wanted.>
```

## Reviewer: Process QA Handoff

Trigger: Oliver says **“`<Reviewer>` QA takeoff”** (for example **“Artanis QA takeoff”**), **“Process
`<Coworker>`'s QA handoff”**, or an unambiguous equivalent, to the agent that will test.

1. Select the pair as `common.md` specifies, scanning only `qa-request-*.md`.
2. Complete the identity and safety checks and load applicable project instructions. No stack
   guidelines are needed. `Coworker` and `Reviewer` must be valid as in `review.md`, differ, and
   `Coworker` must match the filename. Otherwise report and stop.
3. Confirm the tool, reachability, and observed build before executing any case.
4. Execute each case within the safety boundary. Record failures with exact reproduction steps and
   evidence. Note issues outside the cases separately; never fold them into the verdict.
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
- Station: <masterchief|hades>
- Lane: <station-flow lane value>
- Handoff ID: <copied exactly from the request>
- Tested: <ISO-8601 timestamp>
- Coworker: <copied exactly from the request>
- Reviewer: <the testing agent>
- Reviewer override: <Oliver-directed (request named <name>) — include only when applicable>
- Repository: <canonical absolute path>
- Branch: <copied exactly from the request>
- Build under test: <copied exactly from the request>
- Build observed: <what the running app showed, or “not visible”>
- App URL: <URLs actually used>
- Tool: <browser or automation tool used>
- Verdict: <passed|failed|blocked|partial>

## Summary

<Concise assessment and case counts by result.>

## Results

### QA-<n> — <pass|fail|blocked|not-run>: <title>

- Observed: <what happened>
- Expected: <copied from the request>
- Reproduce: <exact steps taken; required for fail>
- Evidence: <paths under qa-evidence-<coworker>/, or “none”>
- Console and network: <errors seen, or “none”>

## Data Created or Changed

<Records created or modified, for cleanup, or “none”.>

## Observations Outside the Requested Cases

<Issues noticed but not requested, or “None”.>

## Questions for Oliver and the Coworker

<Decisions or missing context, or “None”.>
```

## Coworker: Process the QA Report

Trigger: Oliver says **“Process `<Reviewer>`'s QA report”** (for example **“Process Artanis's QA
report”**) or an unambiguous equivalent. Follow `common.md`, classifying every non-passing case as
`bug`, `environment or data`, `wrong expectation`, or `uncertain`. Analysis only; stop for Oliver.
