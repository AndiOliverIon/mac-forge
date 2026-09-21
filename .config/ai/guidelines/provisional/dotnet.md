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
