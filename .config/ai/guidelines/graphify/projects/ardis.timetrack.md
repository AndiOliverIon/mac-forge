# TimeTrack Graph Profile — Hades

Use with `~/.config/ai/guidelines/graphify.md` only for a requested `ardis.timetrack` consultation.
This is a Hades-only experiment. All paths and commands are local to Hades; do not configure access
from another station as part of a consultation.

## Locations

| Item | Absolute path |
| --- | --- |
| Indexed primary checkout | `/Users/oliver/work/ardis.timetrack` |
| Graph directory | `/Users/oliver/graphify/ardis.timetrack/graphify-out` |
| CLI | `/Users/oliver/.local/bin/graphify` |
| Status/refresh helper | `/Users/oliver/graphify/bin/timetrack-graph` |
| Human operational reference | `/Users/oliver/graphify/GRAPHIFY-REFERENCE.md` |

The graph directory contains `graph.json` (queryable relationships), `GRAPH_REPORT.md` (overview and
coverage warnings), and `graph.html` with its local `assets/` (interactive community view).
Configuration and maintenance records are beside that directory, under
`/Users/oliver/graphify/ardis.timetrack/`: `project.json`, `last-refresh.json`, and `maintenance.log`.
The registered CLI was `graphifyy[sql]` 0.9.99; no semantic/LLM backend is configured.

## Freshness and permitted refresh

```sh
/Users/oliver/graphify/bin/timetrack-graph status
```

Check `exit_code`, `graph_modified_utc`, `graph_built_at_commit`, `current_head`,
`source_moved_during_refresh`, and `tracked_working_tree_changes`. The helper describes the indexed
primary checkout; compare its graph revision with the task's own checkout too.

If the task targets that primary checkout and the graph needs updating, Oliver's consultation
request permits this source-preserving refresh; wait for completion and recheck status:

```sh
/Users/oliver/graphify/bin/timetrack-graph refresh
```

Use the helper to preserve saved exclusions and the offline visualization. Do not automatically
use `--force` or `rebuild`. For a different checkout/revision, report the mismatch and verify any
background graph information against that checkout's source.

## Query examples

Substitute task-relevant symbols for these examples:

```sh
graphify_cli=/Users/oliver/.local/bin/graphify
graphify_graph=/Users/oliver/graphify/ardis.timetrack/graphify-out/graph.json
"$graphify_cli" query "TimetrackDbContext" --budget 1200 --graph "$graphify_graph"
"$graphify_cli" explain TimetrackDbContext --graph "$graphify_graph"
"$graphify_cli" path TimetrackDbContext 'Ardis.Timetrack.Data/Entities/ClockEvent.cs::ClockEvent' --undirected --graph "$graphify_graph"
```

## Maintenance and known gaps

- Four local Git hooks refresh after commits, branch switches, merges, and rebases in the indexed
  primary checkout. They run in the background; separate worktrees and other clones are skipped.
  Resets, restores, and uncommitted edits are not all covered. Cached parsing is incremental, but
  graph analysis can still take minutes after source changes.
- Saved exclusions and Git ignore rules omit dependencies, build artifacts, generated API/OpenAPI
  files, and sensitive settings. References to those symbols can exist without implementations;
  client-to-server tracing is therefore incomplete.
- Angular template bindings/styles, some T-SQL constructs and DML scripts, generated mapper details,
  DI/runtime dispatch, reflection, external services, and end-to-end HTTP relationships are
  incomplete or unrepresented. Some files produce no symbols. Framework and test nodes can dominate
  navigation hubs. Consult the report for the current corpus warnings.
- Some Markdown structure is extracted locally. Semantic document/media processing and LLM
  community naming remain disabled. Maintenance/removal procedures belong in the human reference;
  this profile does not authorize changing the existing setup.
