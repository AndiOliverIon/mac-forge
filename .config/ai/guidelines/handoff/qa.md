# Handoff — QA

The Reviewer (Tester) uses the running app like a user and checks that the outcome is what the
Coworker expects. It judges behavior, not code or builds. Hades only: elsewhere, stop and tell Oliver.

## Rules

- QA is the last step of a task, after Coworker, code reviewer, and Oliver agreed on the code review.
  A re-test after a fix is a new request with a new handoff ID.
- Oliver owns the environment: he deploys the app on a disposable VPS1 snapshot database and gives
  the URL. Agents never build, start, deploy, or restore anything for QA.
- Default Tester: Artanis. Artanis, Argus, or Aegis may test only with a working browser or
  app-automation tool in its session; otherwise it reports and stops. Aldaris never tests.
- Files: `qa-request-<coworker>.md`, `qa-report-<coworker>.md` (`Kind: qa`), and the Tester-owned
  owner-only `qa-evidence-<coworker>/`, fully replaced each cycle. Handoff ID: the station format with
  `qa` before the coworker token. No autonomous loop.
- On the given URL the Tester decides and performs any operation the cases need, data changes
  included, without asking, unless `Limits` says otherwise. It never tests another URL, runs
  automated test suites (`always/test-execution.md` applies), or edits code or configuration.
- App unreachable or not functional at the URL: stop and tell Oliver. A case needs a snapshot
  restore: stop, ask Oliver, and continue the same handoff after he confirms.
- Credentials from the request are never copied into the report or evidence.

## Coworker: Prepare

Trigger: **“Prep for `<Tester>` QA takeoff”**, **“Prep for QA takeoff”**, **“Hand off to `<Tester>` for
QA”**, **“QA handoff to `<Tester>`”**, or an equivalent, optionally with a depth. No depth means
`medium`.

Oliver gives only the URL and depth; the Coworker derives every case from the task it worked on. The
Tester sees nothing but the request, so it must be self-sufficient. Take the login from the task
context; if the URL or login is missing, ask Oliver.

| Depth | Cases cover |
| --- | --- |
| `surface` | The task's main path and critical outcome. |
| `medium` | Every behavior the task added or changed, including acceptance criteria and error paths. |
| `verbose` | `medium` plus adjacent screens and flows the change could affect. |

Write the request, then tell Oliver its path, handoff ID, Coworker, and Tester.

```md
# QA Request

- Kind: qa
- Status: ready-for-qa
- Station: hades
- Lane: <lane>
- Handoff ID: <ID>
- Created: <ISO-8601>
- Coworker: <name>
- Reviewer: <Tester name>
- Repository: <canonical path>
- Branch: <branch>
- App URL: <URL from Oliver>
- Depth: <surface|medium|verbose>
- Code review: <approved review handoff ID|none>
- Code reviewer: <name|none>
- Task: <key/title|none>

## Objective
<What the user must now be able to do.>

## Access
<Login URL, account, password, role, start area.>

## Preconditions
<Required snapshot state, or none.>

## Test Cases
### QA-<n> — <high|medium|low>: <title>
- Page: <where>
- Steps: <actions; omit only for exploratory cases>
- Expected: <observable result>

## Limits
<Restrictions and areas out of scope, or none.>
```

## Tester: Process

Trigger: **“`<Tester>` QA takeoff”**, **“Process `<Coworker>`'s QA handoff”**, or an equivalent. Select
the pair per `common.md` (scan only `qa-request-*.md`), run the checks, and load project instructions;
no stack guidelines. Confirm the tool and the URL, execute every case, then write the report and
evidence and tell Oliver the path, handoff ID, verdict, case counts, and both names.

Verdict: `passed` all cases passed; `failed` any failed; `blocked` none could run; `partial` some
blocked or not run, none failed. Issues outside the cases never affect the verdict.

```md
# QA Report

- Kind: qa
- Status: qa-complete
- Station: hades
- Lane: <lane>
- Handoff ID: <copied>
- Tested: <ISO-8601>
- Coworker: <copied>
- Reviewer: <you>
- Reviewer override: <only per common.md>
- Repository: <canonical path>
- Branch: <copied>
- App URL: <copied>
- Tool: <tool used>
- Verdict: <passed|failed|blocked|partial>

## Summary
<Assessment and counts per result.>

## Results
### QA-<n> — <pass|fail|blocked|not-run>: <title>
- Observed: <what happened>
- Reproduce: <exact steps and data; fail only>
- Evidence: <qa-evidence paths, console and network errors, or none>

## Other Observations
<Issues outside the cases, or none.>

## Questions
<For Oliver and the Coworker, or none.>
```

## Process the Report

Oliver reads each report first, then sends **“Process `<Tester>`'s QA report”** to the Coworker (small
problem), the code reviewer (architectural problem), or both (three-way discussion).

- **Coworker:** follow `common.md` for its own pair.
- **Code reviewer:** scan only `qa-request-*.md` headers for `Code reviewer` = you and `Reviewer` = the
  named Tester, with a matching `qa-complete` report. One selects the pair; several, ask Oliver; none,
  report and stop. Then follow `common.md` steps 2–5, focused on design and architecture causes.

Classify each non-passing case as `bug`, `wrong expectation`, `environment`, or `uncertain`. Analysis
only; change no files; stop for Oliver.
