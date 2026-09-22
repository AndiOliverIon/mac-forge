# PERFORM

<!-- jira-leaf
site: ardis.atlassian.net
project-key: PER
project-id: 10043
components: none
aliases: perform, per, ardis perform, ardis.perform
-->

Identifier set and rules for PERFORM work. Read `../common.md` first for the generic `twg` contract.
The identifiers below are authoritative; never substitute values from memory.

## Identifiers

| Fact | Value |
| --- | --- |
| Site | `ardis.atlassian.net` |
| Project | PERFORM (`PER`, id `10043`) |

This project does not use components — do not query or attach one; a `PER-*` ticket's `components`
field is normally empty.

## Permitted actions

Read-only in this project. Each action still requires Oliver's explicit ask in the turn, per
`../common.md`.

| Action | Allowed |
| --- | --- |
| Read / query | Yes |
| Create | No |
| Edit fields | No |
| Add / edit comments | No |
| Status transitions | No |

No action outside `PER` is authorized here, and no write action is authorized here at all — reads
only, even when Oliver names a specific write and it is not on this list.

## Issue types

| Name | Id | Use |
| --- | --- | --- |
| Story | `10001` | Functionality expressed as a user goal. |
| Task | `10002` | A small, distinct piece of work. |
| Sub-task | `10003` | Child of a larger task; requires `--parent <KEY>`. |
| Bug | `10004` | A problem or error. |
| Sub-bug | `10144` | A bug that is a child of a larger item; requires `--parent <KEY>`. |
| Epic | `10000` | A large story that needs to be broken down. |
| Support | `10145` | A support request. |

Use the type Oliver names; do not substitute one for another. Scope all reads to `project = PER`
(no component clause).
