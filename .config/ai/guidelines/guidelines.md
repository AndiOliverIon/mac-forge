# Shared Guideline Router

This file is the single tool-neutral entry point for deciding which shared guideline files Codex and Claude must load.

## First Step For Every Task

1. The generated global bootstrap embeds `identities.md`, this router, and every direct
   `always/*.md` file. They are already loaded; do not read them again. Determine the preliminary
   mode (`development`, `review`, or `handoff`) from the request, then run
   `~/.config/ai/bin/ai-context.sh --mode <mode> [--repository <path>] [--target <path> ...] [--review-target <target>]`
   and read its complete output. Use `--review-target HEAD`, `working-tree`, `staged`, or a Git diff
   range when the review scope is known.
2. Verify that the resolved station, universe, repository, mode, stacks, and project-instruction
   paths match the task scope and the discovery and stack-selection rules below. Perform only the
   missing read-only inventory when the result is partial, then rerun the resolver with the
   discovered repository or target files. For a task spanning repositories, run it once per
   repository and load the union of the returned paths.
3. Run every `INSTRUCTION_BATCH_N_COMMAND` in numeric order, one command per tool call, before
   substantive analysis, recommendations, findings, or changes. Accept a batch only when its final
   `INSTRUCTION_BATCH_COMPLETE` marker is present. If the reader reports changed content, rerun the
   resolver. If output is incomplete or its completion marker is absent, read that batch's files
   individually. `NEXT_INSTRUCTION_PATHS` remains the authoritative order and manual fallback.
4. If the resolver is unavailable or fails, determine the task mode, inventory the scope, and apply
   the discovery and stack-selection rules below manually.
5. State every `.md` instruction source being used and continue without asking for confirmation. The
   user will interrupt if the source list is wrong.

## Reading Tasks By Number

- See `always/jira-tasks.md` (already loaded) for handling a task by its number/key (e.g. `PER-6792`).

## Task Modes

| Mode | Use for |
| --- | --- |
| **Development / co-work** | Implementing, modifying, refactoring, fixing, or planning/designing a concrete change for implementation. |
| **Review** | Reviewing, checking, inspecting, approving, preparing findings, or read-only investigation, diagnosis, explanation, comparison, or architecture analysis of existing work. |

- A repository-scoped non-code audit that neither inspects nor changes a stack loads only
  always-applicable, provisional general, and project instructions.
- Before moving from read-only investigation to implementation, switch to development mode and state
  the updated source list.
- For a task that changes code and then explicitly reviews the result, use development mode while
  changing it and review mode only for the explicit review step.

## Repository Instruction Discovery

These rules apply even when the resolver succeeds; its result does not replace them.

- For every repository in scope, resolve its canonical repository root even when the session was
  launched from a parent directory, sibling directory, worktree container, or another repository.
  If a task key or description does not identify it, resolve it from the task source of truth and
  actual affected files before substantive work. Load project instructions for every touched
  repository.
- Do not rely only on instructions discovered at session start or by the resolver. Inspect the path
  from each repository root down to the files in scope; at each applicable directory load
  `AGENTS.override.md` when present, otherwise `AGENTS.md`, plus an applicable `CLAUDE.md` and any
  local tool-instruction file that an active instruction source references.
- Repository instructions that are ignored, untracked, or local-only still apply.
- If repository ownership or the applicable project instruction chain remains uncertain, report the
  uncertainty and use the more inclusive instruction set. Never silently omit project instructions.

## Stack Guideline Selection

1. Enumerate the actual files in scope: exact changed files from the authoritative review target, or
   development targets and directly affected dependencies. Do not select from the ticket title,
   user summary, or intended primary area alone.
2. Use file paths, extensions, project metadata, and relevant contents to load the union of all
   represented stacks (paths under `~/.config/ai/guidelines/`). The resolver is not exhaustive; for
   example, it detects operations work only from Docker files. Load any represented stack it missed.
   - Every repository-scoped development or review task: `provisional/general.md`
   - Angular / TypeScript / frontend: for development, `stacks/angular-development.md`; for review,
     `stacks/angular-review/_core.md` plus every topic file whose trigger in the core table matches
     the enumerated files; then `provisional/angular.md`. Load exactly the set selected by task
     mode, never both.
   - .NET / C# / backend: `stacks/dotnet.md`, then `provisional/dotnet.md`
   - MSSQL / stored procedures / database: `stacks/sql.md`, then `provisional/sql.md`
   - Deployment, provisioning, remote-server work, or Docker-hosted database operations:
     `stacks/ops.md`
3. Re-evaluate whenever development scope expands. When an additional stack or Angular topic may
   match, include it rather than risk silently missing a rule.

Do not read unselected stack or provisional files. Topic selection must follow the selected set's
trigger table, not judgment about what the change is primarily "about".

## Priority

- Priority 0: the files in `always/` and the stack guideline files selected by this router.
- Priority 1: project-specific instruction files such as repository `AGENTS.md`, repository `CLAUDE.md`, or local tool instructions.
- Priority 2: the provisional guideline files selected by this router.

Priority 1 files may add project-specific rules, safety constraints, or workflow requirements. They must not contradict Priority 0.
Priority 2 rules are mandatory within their scope but never override sealed Priority 0 or Priority 1
rules. Admit them only when no conflict exists; if a later conflict appears, follow the sealed rule
and bring the provisional rule back to Oliver for a decision.
