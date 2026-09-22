# <Component> — <Project Name>

<!-- jira-leaf
site: <site, e.g. ardis.atlassian.net>
project-key: <KEY, e.g. IA>
project-id: <numeric project id>
components: enforced|none
component: <Component Name>
component-id: <numeric component id>
aliases: <comma-separated names, keys, and synonyms used to match this leaf>
-->

<!--
Filename convention:
  components: enforced -> <project-key-lower>-<component-slug>.md
    component-slug = component name lowercased, spaces and punctuation turned into hyphens.
    Examples: TimeTrack -> ia-timetrack.md, OPPO Editor -> ia-oppo-editor.md.
  components: none -> <project-key-lower>.md (one leaf covers the whole project).
    Example: PER -> per.md.
Files beginning with `_` (like this template) are ignored by the header-scan.
Keep `aliases` specific so no two leaves match the same word.

`components` is declared once per project and never rediscovered with a `twg jira space component
query` once a leaf states it. If `components: none`, delete the `component` and `component-id` header
lines, the "Component" and "Component field on create" identifier rows below, and every component
mention in Permitted actions / Issue types.
-->

Identifier set and rules for <Component> work. Read `../common.md` first for the generic `twg`
contract. The identifiers below are authoritative; never substitute values from memory.

## Identifiers

| Fact | Value |
| --- | --- |
| Site | `<site>` |
| Project | <Project Name> (`<KEY>`, id `<project-id>`) |
| Component | `<Component>` (id `<component-id>`) — omit this row when `components: none` |
| Component field on create | `--field 'components=[{"id":"<component-id>"}]'` (no `--components` on create) — omit when `components: none` |

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

No action outside `<KEY>` (/ `<Component>` when `components: enforced`) is authorized here. On create
or edit, attach only the `<Component>` component (id `<component-id>`); never add or leave any other
component. When `components: none`, drop the component clause entirely — there is no component to
attach or restrict.

## Issue types

| Name | Id | Use |
| --- | --- | --- |
| Bug | `<id>` | A problem or error. |
| Task | `<id>` | A small, distinct piece of work. |
| Story | `<id>` | Functionality expressed as a user goal. |
| Epic | `<id>` | A large story that needs to be broken down. |
| Sub-task | `<id>` | Child of a larger task; requires `--parent <KEY>`. |

Use the type Oliver names; do not substitute one for another. Scope all reads and creates to
`project = <KEY> AND component = <Component>` (`components: enforced`) or `project = <KEY>` alone
(`components: none`). Quote a component name that contains spaces (`component = "<Component>"`).
