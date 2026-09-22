# <Component> — <Project Name>

<!-- jira-leaf
site: <site, e.g. ardis.atlassian.net>
project-key: <KEY, e.g. IA>
project-id: <numeric project id>
component: <Component Name>
component-id: <numeric component id>
aliases: <comma-separated names, keys, and synonyms used to match this leaf>
-->

<!--
Filename convention: <project-key-lower>-<component-slug>.md
  component-slug = component name lowercased, spaces and punctuation turned into hyphens.
  Examples: TimeTrack -> ia-timetrack.md, OPPO Editor -> ia-oppo-editor.md.
Files beginning with `_` (like this template) are ignored by the header-scan.
Keep `aliases` specific so no two leaves match the same word.
-->

Identifier set and rules for <Component> work. Read `../common.md` first for the generic `twg`
contract. The identifiers below are authoritative; never substitute values from memory.

## Identifiers

| Fact | Value |
| --- | --- |
| Site | `<site>` |
| Project | <Project Name> (`<KEY>`, id `<project-id>`) |
| Component | `<Component>` (id `<component-id>`) |
| Component field on create | `--field 'components=[{"id":"<component-id>"}]'` (no `--components` on create) |

## Permitted actions

Set each to Yes or No. Omitting this table means read-only. Each granted action still requires
Oliver's explicit ask in the turn, per `../common.md`.

| Action | Allowed |
| --- | --- |
| Read / query | <Yes/No> |
| Create | <Yes/No> |
| Edit fields | <Yes/No> |
| Add / edit comments | <Yes/No> |
| Status transitions | <Yes/No> |

No action outside `<KEY>` / `<Component>` is authorized here. On create or edit, attach only the
`<Component>` component (id `<component-id>`); never add or leave any other component.

## Issue types

| Name | Id | Use |
| --- | --- | --- |
| Bug | `<id>` | A problem or error. |
| Task | `<id>` | A small, distinct piece of work. |
| Story | `<id>` | Functionality expressed as a user goal. |
| Epic | `<id>` | A large story that needs to be broken down. |
| Sub-task | `<id>` | Child of a larger task; requires `--parent <KEY>`. |

Use the type Oliver names; do not substitute one for another. Scope all reads and creates to
`project = <KEY> AND component = <Component>`. Quote a component name that contains spaces
(`component = "<Component>"`).
