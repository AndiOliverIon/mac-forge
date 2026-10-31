# Optional Architectural Graphs — Graphify

Only on Oliver's explicit graph-consultation request, identify the task's project and **load only
its matching profile** below. Links are relative to this file. Ask if the project is ambiguous;
never select the only entry by default. If no profile or accessible graph exists, report that and
continue from current source.

## Project registry

| Project | Profile to load |
| --- | --- |
| `ardis.timetrack` / TimeTrack | [TimeTrack](graphify/projects/ardis.timetrack.md) |

For each future project Oliver selects and indexes, add a `graphify/projects/` profile and registry
row. Keep all project paths, commands, and exceptions in that profile.

## Visible graph status

- Before the first lookup, say `Graphify: consulting <project> graph — <absolute graph.json path>.`
  If unresolved, say `Graphify: consultation requested; project not yet resolved.`
- Begin the final answer with `Graphify: used <project> graph.` or `Graphify: not used — <specific reason>.`
  Mention material staleness/revision mismatches; never silently fall back to source.
- "Used" requires consulting architectural content through a query/report; checking instructions,
  existence, or freshness is insufficient. Emit no status for ordinary tasks or editing these guides.
  A missing status can reveal a missed trigger.

## Consultation workflow

1. Confirm the profile's station/checkout match; name this guide and the selected profile as
   instruction sources. Normal project instructions still apply.
2. Check freshness as the profile directs, comparing its graph revision with the task's checkout.
   Inspect failures and local edits; matching commits do not prove uncommitted edits are represented.
   Failed refreshes can leave an older graph.
3. Refresh only as the profile permits. Never force shrinkage, switch branches, reset, or rebuild
   from another worktree to make a graph match. Qualify any stale graph used as background context.
4. Use the profile's CLI with explicit `--graph` for scoped queries/explanations; read the report for
   overviews. Do not load whole graphs, caches, or unrelated profiles. Narrow truncated queries or
   adjust budgets. Exit 3 means ambiguity; 4 means no match. For `explain`/`path`, use `path::Symbol`
   or full node IDs to disambiguate; `query --seed` needs a full node ID.
5. Verify important conclusions against current source, configuration, and runtime behavior.
   `EXTRACTED` and `INFERRED` edges are navigation hints with known gaps; missing edges do not prove
   missing dependencies. Report material coverage limitations.

## Boundaries

Keep analysis local and deterministic. Consultation does not authorize cloud/paid/LLM processing,
installation/upgrades, agent skills/interception hooks, strict enforcement, new indexing, Git
workflow changes, or committing graphs. Do not run installers, `label`, or backend configuration.
Normal routing and build/test approval rules remain in force. Load the profile's operator reference
only when maintenance details are needed.
