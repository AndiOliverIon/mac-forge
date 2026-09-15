# Artanis–Argus Review Handoff — Hades Flow

Use this flow only when the handoff router identifies the local station as `hades`.

Hades uses a local project-lane root rather than MasterChief's fixed agent-universe lanes. This directory is runtime coordination state, not a network service and not content to commit or synchronize through Mac Forge.

## Project and Lane Resolution

1. Resolve the canonical physical Git root for the one repository in handoff scope. Use repository evidence such as `git rev-parse --show-toplevel`; do not derive the lane from a conversational label or the current subdirectory alone.
2. Use the canonical repository root's exact basename as the project key and lane name. It must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Do not silently normalize or rewrite it.
3. Resolve the handoff root as `/Users/oliver/handoffserver` and the lane as `/Users/oliver/handoffserver/<project-key>`.
4. Verify the physical resolved lane remains an immediate child of the physical handoff root. Reject `..`, path separators, symlinked handoff roots, and symlinked lane directories.
5. If an existing lane's active request names a different canonical repository path, stop and ask Oliver to resolve the basename collision. Never silently reuse that lane.

If the repository is not a Git repository, its root is ambiguous, multiple repositories are in scope, or the project key is unsafe, stop and ask Oliver for direction. Do not guess a lane.

## Lane Creation and Isolation

Only the active coworker (Artanis or Karax) may create the handoff root or a missing project lane, and only while processing **“Prep for Argus takeoff”**. Create directories with owner-only access. Each agent must create its owned transporter file with owner-only access; the coworker then creates or completely replaces only `request-<coworker>.md`.

Argus must not create a missing handoff root, lane, or request file. When processing a handoff, a missing or unsafe path is a configuration error: report it and stop.

The active lane uses distinct coworker pairs:

- Artanis request: `/Users/oliver/handoffserver/<project-key>/request-artanis.md`
- Artanis findings: `/Users/oliver/handoffserver/<project-key>/findings-artanis.md`
- Karax request: `/Users/oliver/handoffserver/<project-key>/request-karax.md`
- Karax findings: `/Users/oliver/handoffserver/<project-key>/findings-karax.md`

Different project lanes may operate concurrently, and both coworker pairs in one project lane may be active at once. While operating in one project lane, never enumerate, inspect, read, or modify another project lane. While operating one coworker's pair, never read or write the other coworker's files except as the common protocol allows to detect an ambiguous **“Argus takeoff”**. A new request replaces only that coworker's prior request.

## Metadata and Handoff ID

Use:

- `Station: hades`
- `Lane: <project-key>`
- Handoff ID: `hades:<project-key>:<coworker>:<ISO-8601 timestamp>`

The coworker token is `artanis` or `karax` and must match the transporter filenames.

The project key in the lane path, metadata, and handoff ID must agree, and the coworker token must match the filenames. The canonical absolute repository path recorded in both transporter files of a pair must match the active repository before review or findings analysis proceeds.
