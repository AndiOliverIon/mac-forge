# Handoff Router

The protocol is dormant unless Oliver invokes a handoff command, starts `team-work.sh`, or gives an
unambiguous equivalent instruction. An autonomous team-loop prompt carrying `Automation: team-loop`
and a loop ID is a routed code-review trigger created from Oliver's script invocation.

## Pick the Kind From the Trigger

| Oliver's words | Kind | Resolver mode |
| --- | --- | --- |
| No handoff command | ordinary co-work or review | `development` or `review` |
| Handoff command containing `QA` (“Prep for Artanis QA takeoff”, “Artanis QA takeoff”, “Process Artanis's QA report”) | QA: Reviewer tests the running app | `qa-handoff` |
| Any other handoff command (“Prep for Argus takeoff”, “Argus takeoff”, “Process Argus's findings”) | code review | `handoff` |

Never switch kinds on your own. If the words do not fit one row (for example “go test the login page”
with no handoff command, or “findings” when only a QA report exists), ask Oliver.

## Route Before Acting

- The resolver returns `handoff/common.md`, the kind file (`handoff/review.md` or `handoff/qa.md`), and
  exactly one station flow, derived only from the normalized lowercase short hostname (`masterchief`
  or `hades` → `~/.config/ai/guidelines/handoff/<station>.md`). Without the resolver, load those three
  files manually and completely.
- If the hostname is unknown, ambiguous, or unsafe to determine, stop and ask Oliver. Do not choose
  a flow or inspect or modify transporter files.
- Resolve the active lane through the station flow before touching transporter files; station
  identity overrides path-based guesses. The station flow owns lane discovery, paths, identity, and
  isolation; the common and kind files own roles, file ownership, behavior, and document structure.

Loading this router alone authorizes no lane creation, transporter write, review, testing, result
analysis, or repository change. Each action requires its trigger and the protocol's boundary.
