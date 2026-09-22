# TimeTrack — Internal Apps

<!-- jira-leaf
site: ardis.atlassian.net
project-key: IA
project-id: 10061
component: TimeTrack
component-id: 11845
aliases: timetrack, time track, time tracking, IA/TimeTrack, Internal Apps TimeTrack
-->

Identifier set and rules for TimeTrack work. Read `../common.md` first for the generic `twg` contract.
The identifiers below are authoritative; never substitute values from memory.

## Identifiers

| Fact | Value |
| --- | --- |
| Site | `ardis.atlassian.net` |
| Project | Internal Apps (`IA`, id `10061`) |
| Component | `TimeTrack` (id `11845`) |
| Component field on create | `--field 'components=[{"id":"11845"}]'` (no `--components` on create) |
| Optional custom field | Epic Link `customfield_10014` |

## Permitted actions

Full rights in this project and component. Each action still requires Oliver's explicit ask in the
turn, per `../common.md`.

| Action | Allowed |
| --- | --- |
| Read / query | Yes |
| Create | Yes |
| Edit fields | Yes |
| Add / edit comments | Yes |
| Status transitions | Yes |

No action outside `IA` / `TimeTrack` is authorized here. On create or edit, attach only the
`TimeTrack` component (id `11845`); never add or leave any other Internal Apps component.

## Issue types

| Name | Id | Use |
| --- | --- | --- |
| Bug | `10004` | A problem or error. |
| Task | `10002` | A small, distinct piece of work. |
| Story | `10001` | Functionality expressed as a user goal. |
| Epic | `10000` | A large story that needs to be broken down. |
| Sub-task | `10003` | Child of a larger task; requires `--parent <KEY>`. |

Use the type Oliver names; do not substitute one for another. Scope all reads and creates to
`project = IA AND component = TimeTrack`.
