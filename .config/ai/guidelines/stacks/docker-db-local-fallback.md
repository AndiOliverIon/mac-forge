# Hades Local Docker Database Fallback

Load this file only after `ops.md` selects the local fallback. Do not load it for normal VPS1
database work.

## Entry Conditions

- Local Docker SQL is a Hades-only contingency. Use it only when Oliver explicitly requests it, or
  when VPS1 connectivity is verified unavailable and Oliver confirms changing database targets.
- Never switch silently. State that the operation will use Hades-local data rather than VPS1 and
  identify any expected data-age or environment difference.
- This fallback applies only to Docker-hosted databases. It does not govern local image builds or
  application containers.

## Local Authority and Workflow

- Read `configs/work-state.json` before acting. Its `docker-path`, `docker-snapshot-path`, and
  `docker-locations` values are authoritative for the local fallback; do not hardcode alternatives.
- The established defaults are container `forge-sql`, host port `2022`, user `sa`, and image
  `mcr.microsoft.com/mssql/server:2022-latest`. Verify actual script/config values before use rather
  than relying on this summary.
- Use the existing Mac Forge workflow: select storage with `scripts/work.sh`, ensure the local SQL
  container, restore through `scripts/db-restore.sh`, snapshot through `scripts/db-snapshot.sh` when
  needed, and clean through `scripts/db-clear.sh` only with its safeguards and confirmations.
- Prefer existing local helpers over ad-hoc Docker or SQL commands. Inspect the relevant helper and
  current operational state before running it.

## Data and Exit Safety

- Do not assume local data matches VPS1. Record the database target in validation and handoff notes.
- Never upload, restore, merge, or otherwise propagate local fallback data to VPS1 without Oliver's
  explicit authorization and an exact source, destination, and recovery plan.
- Returning normal work to VPS1 changes the database target; verify VPS1 connectivity and state
  explicitly rather than treating the transition as automatic.
