# Jira Tasks — Common Protocol

This file applies only after the dormant Jira pointer in `always/jira-tasks.md` is triggered in the
current turn. Oliver remains the decision-maker. It defines two things: how to select the right
project leaf, and the tool contract that is identical across every project. Project-specific facts
(site, project key/id, component id, issue-type ids) live only in the leaf you select.

## Select the Project Leaf (header-scan)

The `projects/` directory is the registry; each leaf describes itself in a header block. Do not keep a
routing table here and do not resolve a project from memory.

1. Determine the target from the request, in this precedence order:
   - an explicit issue key (e.g. `IA-807`) fixes the project by its key prefix;
   - a named project and component (e.g. "Internal Apps / TimeTrack");
   - a product or app synonym (e.g. "the timetrack app").
2. Enumerate `~/.config/ai/guidelines/jira/projects/*.md`, ignoring any file whose name begins with
   `_` (templates), and read only each remaining file's `jira-leaf` header block. Match the target
   against the header's `project-key`, `component`, and `aliases`.
3. Exactly one match: load that full leaf and use its identifiers. Zero matches: stop and ask Oliver
   which project and component to use, and when no leaf exists for a project he names, offer to create
   one from `projects/_template.md`. More than one match (e.g. a bare issue key against a project with
   several component leaves): stop and ask which component — except the read-only fast path below.
   Never guess a site, project, or component.
   - **Read-only fast path:** when the request is a direct lookup of a single item by its known issue
     key (a `get`, not a search) and every matched candidate leaf grants `Read / query: Yes`, you may
     read that item without asking, using the project facts the candidates share — the key alone
     identifies the item, so no component filter is needed. Any read that needs a JQL search still
     requires a single resolved leaf (ask which component) so each leaf's `project = <KEY> AND
     component = <Component>` scoping is honored. Do not create, edit, comment, or transition until
     Oliver names the component and the single leaf is resolved.
4. As a fast path you may open `<project-key-lower>-<component-slug>.md` directly (the component slug
   is the component name lowercased with spaces and punctuation turned into hyphens, e.g. `TimeTrack`
   → `ia-timetrack.md`, `OPPO Editor` → `ia-oppo-editor.md`), but still confirm the header matches the
   target before acting.

Each leaf header uses this shape:

```md
<!-- jira-leaf
site: <site>
project-key: <KEY>
project-id: <id>
component: <Component Name>
component-id: <id>
aliases: <comma-separated names, keys, and synonyms>
-->
```

The header's identifiers are authoritative. If a `twg` response names a different site or project than
the selected leaf, stop.

## Tool

Use the TWG CLI, not the browser and not a guessed REST call.

```bash
twg <command>
```

The authenticated `twg` CLI already resolves the correct site. Do not run `twg` setup, login, install,
or credential commands unless Oliver explicitly asks for auth repair. If the shell reports
`command not found`, retry with `$HOME/.local/bin/twg` and say that directory is missing from `PATH`.
An auth or permission error is not a `PATH` problem.

Before an unfamiliar mutation, read the live contract and prefer it over any documented flag if they
disagree:

```bash
twg help describe "jira workitem create"
twg help describe "jira workitem update"
twg help describe "jira workitem transition"
```

## Read Before Writing

- Confirm the project and component from the leaf if an id is rejected, using `twg jira space query`
  and `twg jira space component query`.
- Before creating, search for an existing match with `twg jira workitem query --jql '...'`. Quote a
  component name that contains spaces (`component = "DEMO TOOL"`). If a close match is already open,
  show Oliver the key and URL and wait, unless he already said to create anyway.
- Read one item with `twg jira workitem get <KEY> --fields ...`. Plain `get` is the authoritative read;
  request only the fields needed. Add `--comments` only when the thread matters; do not combine
  `--full` with `--comments`.

## Create

- Discover create fields for the chosen type before the first create in a session, and again if Jira
  rejects the payload: `twg jira workitem field create-metadata --space <KEY> --type <Type>`.
- If metadata marks a field required and Oliver did not supply a value, stop and ask. Do not invent
  priority, assignee, sprint, story points, labels, or resolution.
- `create` has no `--components` flag; set the component with `--field 'components=[{"id":"<id>"}]'`
  using the component id from the leaf. `--field` values parse as JSON when valid JSON; do not pass the
  same field through both `--field` and `--fields-json`.
- A sub-task also needs `--parent <KEY>`.

Description rules:

- Pass `--description-format plain` for plain text, or `markdown` when Oliver supplied markdown.
- The default format is `html`. Do not rely on the default for ordinary prose.
- Jira wiki markup is rejected.

## Modify

- Read the current item first, then change only the fields Oliver named. `--id` is required on
  `twg jira workitem update`.
- For a custom field, discover editable fields first with `twg jira workitem field update-metadata
  --id <KEY>` (add `--include-system-fields` when needed) and use the returned `customfield_*` id.
- `--components` replaces the whole component list; use `--add-components <Component>` to attach without
  removing others, and `--remove-components` only when Oliver asked to take a component off.
- `--labels` replaces all labels; use `--add-labels` / `--remove-labels` for a partial edit.
- `--type <Name>` changes the issue type; use a name from the leaf's table.
- `--assignee me` assigns the authenticated user, `--assignee none` unassigns. Do not pick another
  person unless Oliver named that account.
- `--parent <KEY>` sets a parent, `--parent none` clears it.
- Prefer a separate comment command when a comment is the only change:
  `twg jira workitem comment create --issue-id <KEY> --body "..." --body-format plain`. Edit a comment
  only with its comment id and only when Oliver asked to change that comment.

## Status Changes

- Do not guess a transition id. Discover first — omitting `--transition-id` is read-only:
  `twg jira workitem transition --id <KEY>`. Then call it again with one returned `--transition-id`.
- If a transition lists required screen fields and Oliver did not supply them, ask. A request to cancel
  or close does not imply a Resolution such as `Won't Do`, `Declined`, or `Duplicate`.
- `--status` on `jira workitem update` is a second transition path; prefer the discovery command so
  required fields are visible before the write.

## Verify

After every create or update, read the item back with `twg jira workitem get <KEY> --fields ...` and
report `https://<site>/browse/<KEY>`. Confirm the project, issue type, component, summary, and
description match what Oliver requested.

## Safety Invariants

- Mutate Jira only in a turn where Oliver explicitly asks for that create, update, comment, or
  transition. Reading is not permission to write.
- Respect the selected leaf's **Permitted actions** table: never perform an action it does not grant,
  even if Oliver asks. If he asks for an action the leaf withholds, say it is not permitted for that
  project and stop. If a leaf omits the table, treat it as read-only (every action except read is not
  permitted).
- One request concerns one project and component. For work spanning several, stop and ask Oliver to
  pick one or authorize them separately.
- Never file work under a project or component the selected leaf forbids.
- Treat the leaf's identifiers as the source of truth; never substitute values remembered from another
  session.
