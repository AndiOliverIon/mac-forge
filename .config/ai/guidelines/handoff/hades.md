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

Only Artanis may create the handoff root or a missing project lane, and only while processing **“Prep for Argus takeoff”**. Create directories with owner-only access. Each agent must create its owned transporter file with owner-only access; Artanis then creates or completely replaces only `request.md`.

Argus must not create a missing handoff root, lane, or `request.md`. When processing a handoff, a missing or unsafe path is a configuration error: report it and stop.

The active lane uses exactly:

- Request: `/Users/oliver/handoffserver/<project-key>/request.md`
- Findings: `/Users/oliver/handoffserver/<project-key>/findings.md`

Different project lanes may operate concurrently. While operating in one project lane, never enumerate, inspect, read, or modify another project lane. One project lane has only one active handoff cycle; a new request replaces the prior request according to the common protocol.

## Metadata and Handoff ID

Use:

- `Station: hades`
- `Lane: <project-key>`
- Handoff ID: `hades:<project-key>:<ISO-8601 timestamp>`

The project key in the lane path, metadata, and handoff ID must agree. The canonical absolute repository path recorded in both transporter files must match the active repository before review or findings analysis proceeds.
