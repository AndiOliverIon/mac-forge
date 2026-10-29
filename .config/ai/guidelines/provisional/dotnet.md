# Provisional .NET Rules

- For entity-wide progress or overview queries, derive the population from the entity relationship
  itself. Do not narrow it through current worklist state or workcell or group allocation unless the
  contract explicitly defines a contextual snapshot.
- Keep entity-to-DTO mapping independent of runtime license and settings state. Enforce feature
  availability outside the mapper rather than rewriting mapped DTO properties.
- For HTTP endpoints, declare required license modules through the shared controller or action
  authorization attribute and let it raise the established license exception. Do not duplicate that
  enforcement in endpoint-specific helpers or managers solely for the same HTTP path.
- For non-HTTP entry points, report license denial through the established license-exception and
  transport-feedback pipeline rather than returning feature-specific booleans or implementing custom
  SignalR or UI feedback.
- Keep entity business-logic classes free of workflow orchestration such as worklist, container or
  session state; they only select the entity's work and execute it. Evaluate, validate and start the
  workflow at the orchestrating entry point or in the workflow's manager, checking each precondition
  in one layer only, and mirror the layering of the nearest sibling flow.
