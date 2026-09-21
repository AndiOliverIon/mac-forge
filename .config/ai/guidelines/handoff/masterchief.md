# Review Handoff — MasterChief Flow

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

The common Coworker/Reviewer protocol applies in all three lanes, with Argus as the default Reviewer
and any of Artanis, Karax, Argus, or Aegis eligible for either role when Oliver explicitly asks.
The Coworker owns `request-<coworker>.md`; the pair's designated Reviewer owns the matching
`findings-<coworker>.md`. Both files include `Coworker` and `Reviewer`.

Role switching never changes lane rules:

- **Work** is the operator-assisted lane; Coworker and Reviewer may be any two agents Oliver runs
  there.
- **Raynor** and **Zeratul** are isolated universes with one agent per universe. A handoff there is
  played sequentially by whichever agents Oliver assigns to that universe in turn. A role switch
  never authorizes a second concurrent agent, and a Reviewer from another universe or lane is never
  consulted.

## Fixed Paths

### Lane `work`

- Request: `/home/oliver/work/.ai/review-handoff/request-<coworker>.md`
- Findings: `/home/oliver/work/.ai/review-handoff/findings-<coworker>.md`

### Lane `zeratul`

- Request: `/home/oliver/zeratul/.ai/review-handoff/request-<coworker>.md`
- Findings: `/home/oliver/zeratul/.ai/review-handoff/findings-<coworker>.md`

### Lane `raynor`

- Request: `/home/oliver/raynor/.ai/review-handoff/request-<coworker>.md`
- Findings: `/home/oliver/raynor/.ai/review-handoff/findings-<coworker>.md`

`<coworker>` is the lowercase identity of the Coworker (`artanis`, `karax`, `argus`, or `aegis`). The
Reviewer is recorded in the file headers, not the filename.

These lane directories are created and validated by `ai-config install`. Do not create or relocate
them as part of a handoff. If the selected lane directory is missing, stop and report the
configuration problem.

## Metadata and Handoff ID

Use:

- `Station: masterchief`
- `Lane: <work|zeratul|raynor>`
- Handoff ID: `<lane>:<repository-name>:<coworker>:<ISO-8601 timestamp>`

The repository name is the basename of the canonical repository root. The lane and coworker token in
the metadata, handoff ID, and transporter filenames must agree. `Reviewer` is a header field only.

Keep the `Branch` and `Review target` metadata values on one line so the Linux handoff validator can
compare them exactly. Run `~/.config/ai/bin/review-handoff-verify.sh <lane>` after preparing or
writing a handoff file. Validate each coworker pair independently, including that `Coworker` and
`Reviewer` are distinct valid identities. A different findings ID is valid
only while it represents that coworker's prior review and the current request in the same pair is
newer; a findings file newer than a differently identified request in the same pair is an invalid
reversed stale pair.
