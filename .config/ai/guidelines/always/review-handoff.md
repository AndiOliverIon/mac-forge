# Review Handoff Router

The protocol is dormant unless Oliver invokes a handoff command, starts `team-work.sh`, or gives an
unambiguous equivalent instruction. Default roles are Artanis as Coworker and Argus as
Reviewer; when Oliver explicitly names another pairing (e.g. Aegis hands off to Artanis), the common
protocol governs the switch. An autonomous team-loop prompt carrying `Automation: team-loop` and a
loop ID is a routed handoff trigger created from Oliver's script invocation.

## Route Before Acting

- The handoff-mode resolver returns `~/.config/ai/guidelines/handoff/common.md` and exactly one
  station flow, derived only from the normalized lowercase short hostname (`masterchief` or
  `hades` → `~/.config/ai/guidelines/handoff/<station>.md`). Without the resolver, load those two
  files manually and completely.
- If the hostname is unknown, ambiguous, or unsafe to determine, stop and ask Oliver. Do not choose
  a flow or inspect or modify transporter files.
- Resolve the active lane through the station flow before touching transporter files; station
  identity overrides path-based guesses. The station flow owns lane discovery, paths, identity, and
  isolation; the common protocol owns roles, file ownership, review behavior, and document structure.

Loading this router alone authorizes no lane creation, transporter write, review processing, findings
analysis, or repository change. Each action requires its trigger and the common protocol's boundary.
