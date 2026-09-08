# Artanis–Argus Review Handoff — MasterChief Flow

Use this flow only when the handoff router identifies the local station as `masterchief`.

## Lane Resolution

Resolve the active Linux context from the canonical physical path of the current repository or requested scope:

- A path at or below `/home/oliver/work` selects lane `work`.
- A path at or below `/home/oliver/zeratul` selects lane `zeratul`.
- A path at or below `/home/oliver/raynor` selects lane `raynor`.

The Work lane is available only from a normal MasterChief shell without an active
`FORGE_UNIVERSE_ROOT`. Raynor and Zeratul are available only from a session assigned to the matching
universe. A tool may have broader read permissions, but the agent must act only inside the selected
lane. If the path belongs to no lane, spans lanes, conflicts with the assigned universe, or cannot be
resolved safely, stop and ask Oliver which context should handle the handoff.

Never inspect another context to discover a repository or infer a lane. While working in one context,
never read or write another context's transporter files.

## Linux Role Assignment

For Raynor and Zeratul, the common Artanis-to-Argus ownership applies unchanged: Artanis owns
`request.md` and Argus owns `findings.md`.

For Work only, this section supersedes the common protocol's fixed identity names while retaining
all of its safety and file-ownership rules:

- The active coworker may be Artanis, Argus, or Aegis and owns `request.md` for that cycle.
- The reviewer may be Artanis, Argus, or Aegis, must be explicitly named by Oliver, must differ from
  the coworker, and owns `findings.md` for that cycle.
- Work handoff commands may name the selected reviewer, such as `Prep for Aegis takeoff` or
  `Process Aegis's findings`; these are unambiguous equivalents of the common triggers.
- Work requests and findings add `Coworker` and `Reviewer` metadata fields. Both files must contain
  the same two names, and the current agent must match the role that owns the file it writes.

## Fixed Paths

### Lane `work`

- Request: `/home/oliver/work/.ai/review-handoff/request.md`
- Findings: `/home/oliver/work/.ai/review-handoff/findings.md`

### Lane `zeratul`

- Request: `/home/oliver/zeratul/.ai/review-handoff/request.md`
- Findings: `/home/oliver/zeratul/.ai/review-handoff/findings.md`

### Lane `raynor`

- Request: `/home/oliver/raynor/.ai/review-handoff/request.md`
- Findings: `/home/oliver/raynor/.ai/review-handoff/findings.md`

These lane directories are created and validated by `ai-config install`. Do not create or relocate
them as part of a handoff. If the selected lane directory is missing, stop and report the
configuration problem.

## Metadata and Handoff ID

Use:

- `Station: masterchief`
- `Lane: <work|zeratul|raynor>`
- Handoff ID: `<lane>:<repository-name>:<ISO-8601 timestamp>`

The repository name is the basename of the canonical repository root. The lane in the metadata, handoff ID, and transporter path must agree.

Keep the `Branch` and `Review target` metadata values on one line so the Linux handoff validator can
compare them exactly. Run `~/.config/ai/bin/review-handoff-verify.sh <lane>` after preparing or
writing a handoff file. A different findings ID is valid only while it represents the prior review
and the current request is newer; a findings file newer than a differently identified request is an
invalid reversed stale pair.
