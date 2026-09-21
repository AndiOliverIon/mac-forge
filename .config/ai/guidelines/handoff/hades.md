# Review Handoff — Hades Flow

Use this flow only when the handoff router identifies the local station as `hades`.

Hades is a single execution universe with no Work, Raynor, or Zeratul lanes. It uses a local project-lane root, one lane per repository, rather than MasterChief's fixed agent-universe lanes. Role switching (Coworker and Reviewer) changes nothing about that layout. This directory is runtime coordination state, not a network service and not content to commit or synchronize through Mac Forge.

## Project and Lane Resolution

1. Resolve the canonical physical Git root for the one repository in handoff scope. Use repository evidence such as `git rev-parse --show-toplevel`; do not derive the lane from a conversational label or the current subdirectory alone.
2. Use the canonical repository root's exact basename as the project key and lane name. It must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Do not silently normalize or rewrite it.
3. Resolve the handoff root as `/Users/oliver/handoffserver` and the lane as `/Users/oliver/handoffserver/<project-key>`.
4. Verify the physical resolved lane remains an immediate child of the physical handoff root. Reject `..`, path separators, symlinked handoff roots, and symlinked lane directories.
5. If an existing lane's active request names a different canonical repository path, stop and ask Oliver to resolve the basename collision. Never silently reuse that lane.

If the repository is not a Git repository, its root is ambiguous, multiple repositories are in scope, or the project key is unsafe, stop and ask Oliver for direction. Do not guess a lane.

## Lane Creation and Isolation

Only the active Coworker (any of Artanis, Karax, Argus, or Aegis preparing a review) may create the
handoff root or a missing project lane, and only while processing a prep trigger (**“Prep for Argus
takeoff”**, **“Prep for `<Reviewer>` takeoff”**, or **“Hand off to `<Reviewer>` for review”**). Create
directories with owner-only access. Each agent must create its owned transporter file with owner-only
access; the Coworker then creates or completely replaces only `request-<coworker>.md`.

A Reviewer must not create a missing handoff root, lane, or request file. When processing a handoff,
a missing or unsafe path is a configuration error: report it and stop.

The active lane uses one pair per Coworker, keyed by the Coworker's lowercase identity:

- Request: `/Users/oliver/handoffserver/<project-key>/request-<coworker>.md`
- Findings: `/Users/oliver/handoffserver/<project-key>/findings-<coworker>.md`

`<coworker>` is `artanis`, `karax`, `argus`, or `aegis`. The Reviewer is recorded in the file
headers, not the filename.

Different project lanes may operate concurrently, and several pairs in one project lane may be active
at once. While operating in one project lane, never enumerate, inspect, read, or modify another
project lane. While operating one pair, never read or write another pair's files except as the common
protocol allows for the Reviewer's header scan on a bare takeoff. A new request replaces only that
Coworker's prior request.

## Metadata and Handoff ID

Use:

- `Station: hades`
- `Lane: <project-key>`
- Handoff ID: `hades:<project-key>:<coworker>:<ISO-8601 timestamp>`

The coworker token is `artanis`, `karax`, `argus`, or `aegis` and must match the transporter filenames. `Reviewer` is a header field only.

The project key in the lane path, metadata, and handoff ID must agree, and the coworker token must match the filenames. The canonical absolute repository path recorded in both transporter files of a pair must match the active repository before review or findings analysis proceeds.
