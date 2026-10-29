# Provisional .NET Rules

- Keep entity business-logic classes free of workflow orchestration such as worklist, container or
  session state; they only select and execute the entity's work. Evaluate and start the workflow at
  the orchestrating entry point or in its manager, check each precondition in one layer only, and
  follow the layering of the nearest sibling flow.
- Derive entity-wide progress or overview populations from the entity relationship itself, not from
  current worklist, workcell or group allocation, unless the contract defines a contextual snapshot.
- Keep entity-to-DTO mapping independent of runtime license and settings state; enforce feature
  availability outside the mapper.
- Enforce license modules through the established pipeline: for HTTP endpoints, the shared
  controller or action authorization attribute, without repeating that check in helpers or managers
  for the same path; for non-HTTP entry points, the license exception with transport feedback,
  not feature-specific booleans or custom SignalR or UI feedback.
