# Artanis–Argus Review Handoff — MasterChief Flow

Use this flow only when the handoff router identifies the local station as `masterchief`.

## Lane Resolution

Resolve the active agent universe from the canonical physical path of the current repository or requested scope:

- A path at or below `/home/oliver/zeratul` selects lane `zeratul`.
- A path at or below `/home/oliver/raynor` selects lane `raynor`.

The current session must have access to only its assigned universe. If the path belongs to neither universe, spans both universes, conflicts with the assigned agent identity, or cannot be resolved safely, stop and ask Oliver which universe should handle the handoff.

Never inspect the other universe to discover a repository or infer a lane. While working in one universe, never read or write the other universe's transporter files.

## Fixed Paths

### Lane `zeratul`

- Request: `/home/oliver/zeratul/.ai/review-handoff/request.md`
- Findings: `/home/oliver/zeratul/.ai/review-handoff/findings.md`

### Lane `raynor`

- Request: `/home/oliver/raynor/.ai/review-handoff/request.md`
- Findings: `/home/oliver/raynor/.ai/review-handoff/findings.md`

These lane directories are part of the prepared MasterChief agent environments. Do not create or relocate them as part of a handoff. If the selected lane directory is missing, stop and report the configuration problem.

## Metadata and Handoff ID

Use:

- `Station: masterchief`
- `Lane: <zeratul|raynor>`
- Handoff ID: `<lane>:<repository-name>:<ISO-8601 timestamp>`

The repository name is the basename of the canonical repository root. The lane in the metadata, handoff ID, and transporter path must agree.
