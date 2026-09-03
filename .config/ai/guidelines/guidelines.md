# Shared Guideline Router

This file is the single tool-neutral entry point for deciding which shared guideline files Codex and Claude must load.

## First Step For Every Task

1. The generated global bootstrap embeds `identities.md`, this router, and every direct
   `always/*.md` file. They are already loaded; do not read them again. Use the resolved context
   emitted by `~/.config/ai/bin/ai-context.sh` for dynamic routing.
2. Verify that the resolved station, universe, repository, mode, stacks, and project-instruction
   paths match the task scope. Perform only the missing read-only inventory when the result is
   partial, then rerun the resolver with the discovered repository or target files.
3. Run every `INSTRUCTION_BATCH_N_COMMAND` in numeric order, one command per tool call, before
   substantive analysis, recommendations, findings, or changes. Accept a batch only when its final
   `INSTRUCTION_BATCH_COMPLETE` marker is present. If the reader reports changed content, rerun the
   resolver. If output is incomplete or its completion marker is absent, read that batch's files
   individually. `NEXT_INSTRUCTION_PATHS` remains the authoritative order and manual fallback.
4. If the resolver is unavailable or fails, fall back to reading every direct `always/*.md` file in
   lexical order, determine the task mode, inventory the scope, and follow the manual discovery and
   stack-selection rules below.
5. State every `.md` instruction source being used and continue without asking for confirmation. The
   user will interrupt if the source list is wrong.

## Reading Tasks By Number

- When told to read, open, or look up a task by its number/key (e.g. `PER-6792`), always use the TWG Jira CLI (`twg jira workitem get <KEY>`) as the source of truth.

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

- For every repository in scope, resolve its canonical repository root even when the session was launched from a parent directory, sibling directory, worktree container, or another repository.
- Do not rely only on instructions that the tool discovered at session start. Manually inspect the path from each repository root down to the files in scope.
- At each applicable directory, load `AGENTS.override.md` when present; otherwise load `AGENTS.md`. Also load an applicable `CLAUDE.md` and any local tool-instruction file that an active instruction source references.
- Repository instructions that are ignored, untracked, or local-only still apply.
- If a task key or user description does not identify the repository directly, resolve the repository from the task source of truth and actual affected files before substantive work.
- If more than one repository is touched, load the applicable project instructions for every one of them.
- If repository ownership or the applicable project instruction chain remains uncertain, report the uncertainty and use the more inclusive instruction set. Never silently omit project instructions.

## Stack Guideline Selection

Select stacks through this deterministic sequence:

1. Enumerate the actual files in scope: exact changed files from the authoritative review target, or
   development targets and directly affected dependencies. Do not select from the ticket title,
   user summary, or intended primary area alone.
2. For every repository-scoped development or review task, load
   `~/.config/ai/guidelines/provisional/general.md`.
3. Use file paths, extensions, project metadata, and relevant contents to load the union of all
   represented stacks:
   - Angular / TypeScript / frontend development:
     `~/.config/ai/guidelines/stacks/angular-development.md`, then
     `~/.config/ai/guidelines/provisional/angular.md`
   - Angular / TypeScript / frontend review:
     `~/.config/ai/guidelines/stacks/angular-review/_core.md`, then every topic file whose trigger
     matches the enumerated files according to the core table, then
     `~/.config/ai/guidelines/provisional/angular.md`
   - .NET / C# / backend: `~/.config/ai/guidelines/stacks/dotnet.md`, then
     `~/.config/ai/guidelines/provisional/dotnet.md`
   - MSSQL / stored procedures / database: `~/.config/ai/guidelines/stacks/sql.md`, then
     `~/.config/ai/guidelines/provisional/sql.md`
   - Deployment, provisioning, remote-server work, or Docker-hosted database operations:
     `~/.config/ai/guidelines/stacks/ops.md`
4. For Angular, load exactly the development set or the review set selected by task mode, never both.
5. Re-evaluate whenever development scope expands. When an additional stack or Angular topic may
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
