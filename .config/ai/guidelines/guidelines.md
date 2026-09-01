# Shared Guideline Router

This file is the single tool-neutral entry point for deciding which shared guideline files Codex and Claude must load.

## First Step For Every Task

- Read every `.md` file directly inside `~/.config/ai/guidelines/always/`, in lexical filename order. The directory may be empty.
- Resolve every repository that owns files in the requested or discovered scope. Do not assume the session's initial working directory is the repository being changed or reviewed.
- Determine the task mode before reading stack-specific guidelines.
- Perform only the read-only routing inventory needed to identify repositories, changed or affected files, task mode, and stacks. Routing inventory is not substantive implementation or review.
- Load every applicable project instruction source and every stack guideline selected below before substantive analysis, findings, recommendations, or changes.
- Explicitly state which `.md` files are being used as instruction sources for the task.
- Do not ask the user to confirm the list. Continue after presenting it.
- If the user sees the wrong sources, they will interrupt or cancel the task.

## Reading Tasks By Number

- When told to read, open, or look up a task by its number/key (e.g. `PER-6792`), always use the TWG Jira CLI (`twg jira workitem get <KEY>`) as the source of truth.

## Task Modes

- **Development mode** (also called **co-work mode**): implementing, modifying, refactoring, fixing, planning a concrete change, or otherwise changing code or configuration without being asked to perform a review.
- **Review mode**: reviewing, checking, inspecting, approving, preparing review findings, or performing read-only analysis or diagnosis of existing code or an existing change.

Mode rules for ambiguous requests:

- Read-only investigation, diagnosis, explanation, comparison, or architecture analysis of existing code uses review mode for guideline selection, even when the user did not ask for formal review findings.
- Design or analysis whose immediate purpose is to implement a new change uses development mode.
- A non-code audit that does not inspect or change a stack uses the always-applicable and project instruction sources only.
- When the task changes from read-only investigation to implementation, switch from review mode to development mode before editing and state the updated source list.

If a task includes both making changes and reviewing the final result, use development mode while changing code, then review mode only for the explicit review step.

## Repository Instruction Discovery

- For every repository in scope, resolve its canonical repository root even when the session was launched from a parent directory, sibling directory, worktree container, or another repository.
- Do not rely only on instructions that the tool discovered at session start. Manually inspect the path from each repository root down to the files in scope.
- At each applicable directory, load `AGENTS.override.md` when present; otherwise load `AGENTS.md`. Also load an applicable `CLAUDE.md` and any local tool-instruction file that an active instruction source references.
- Repository instructions that are ignored, untracked, or local-only still apply.
- If a task key or user description does not identify the repository directly, resolve the repository from the task source of truth and actual affected files before substantive work.
- If more than one repository is touched, load the applicable project instructions for every one of them.
- If repository ownership or the applicable project instruction chain remains uncertain, report the uncertainty and use the more inclusive instruction set. Never silently omit project instructions.

## Stack Guideline Selection

- Angular / TypeScript / frontend code in development mode: `~/.config/ai/guidelines/stacks/angular-development.md`
- Angular / TypeScript / frontend code in review mode: `~/.config/ai/guidelines/stacks/angular-review/_core.md`, plus the topic files selected by the table inside it
- .NET / C# / backend code: `~/.config/ai/guidelines/stacks/dotnet.md`
- MSSQL / stored procedures / database code: `~/.config/ai/guidelines/stacks/sql.md`
- Deployment, provisioning, or any work touching a remote server (e.g. vps1): `~/.config/ai/guidelines/stacks/ops.md`

For Angular work, never load both Angular guideline sets for the same task mode. Use exactly one:

- development mode: `angular-development.md`
- review mode: `angular-review/_core.md`, plus the topic files selected by the table inside it

If a task spans multiple stacks, load each relevant stack guideline selected by the rules above.

Select stacks from the actual scope, not from the ticket title, user summary, or intended primary area alone:

- For reviews, enumerate the exact changed files from the authoritative review target before selecting stack guidelines.
- For development, inspect the target files and directly affected dependencies before selecting stack guidelines, then repeat selection whenever the implementation expands into another stack.
- Use file paths, extensions, project metadata, and relevant file contents as the selection evidence.
- When a file or change may belong to an additional stack, load that stack guideline. The cost of one extra relevant guideline is lower than silently missing a rule.
- A task that touches Angular/frontend, .NET/backend, SQL/database, or operations in combination loads the union of those stack guidelines.

Do not automatically read every file in `stacks/`. Stack guideline sets that this router did not select must remain unloaded.

A stack guideline may be a single file or a directory containing a `_core.md` plus topic files. When a set is selected, always load its `_core.md`, then load each topic file whose trigger matches the code under review. Enumerate the changed files before choosing; selection must follow the set's trigger table, not judgment about what the change is "about". When unsure whether a trigger matches, load the file.

## Angular Guideline Synchronization

- `angular-development.md` is the compact implementation-time expression of the rules in the Angular review set.
- Any added, removed, or materially changed Angular rule must update both the development file and its detailed review home in the same change, unless the rule is explicitly labeled as mode-specific.
- Mode-specific rules must say why they apply only during development or only during review.
- Do not accept an Angular guideline change when equivalent rule intent has silently drifted between the two modes.

## Priority

- Priority 0: the files in `always/` and the stack guideline files selected by this router.
- Priority 1: project-specific instruction files such as repository `AGENTS.md`, repository `CLAUDE.md`, or local tool instructions.

Priority 1 files may add project-specific rules, safety constraints, or workflow requirements. They must not contradict Priority 0.
