# DEMO TOOL — Internal Apps

<!-- jira-leaf
site: ardis.atlassian.net
project-key: IA
project-id: 10061
component: DEMO TOOL
component-id: 10361
aliases: demo tool, demotool, DEMO TOOL, IA/DEMO TOOL, Internal Apps DEMO TOOL
-->

Identifier set and rules for DEMO TOOL work. Read `../common.md` first for the generic `twg` contract.
The identifiers below are authoritative; never substitute values from memory.

## Identifiers

| Fact | Value |
| --- | --- |
| Site | `ardis.atlassian.net` |
| Project | Internal Apps (`IA`, id `10061`) |
| Component | `DEMO TOOL` (id `10361`) |
| Component field on create | `--field 'components=[{"id":"10361"}]'` (no `--components` on create) |
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

No action outside `IA` / `DEMO TOOL` is authorized here. On create or edit, attach only the
`DEMO TOOL` component (id `10361`); never add or leave any other Internal Apps component.

## Issue types

| Name | Id | Use |
| --- | --- | --- |
| Bug | `10004` | A problem or error. |
| Task | `10002` | A small, distinct piece of work. |
| Story | `10001` | Functionality expressed as a user goal. |
| Epic | `10000` | A large story that needs to be broken down. |
| Sub-task | `10003` | Child of a larger task; requires `--parent <KEY>`. |

Use the type Oliver names; do not substitute one for another. Scope all reads and creates to
`project = IA AND component = "DEMO TOOL"`.
