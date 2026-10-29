# Provisional Angular Rules

- Reserve `views` for route entry, landing and page-level components. Place components rendered
  inside them under `features/<domain>`, named for the content or role they render, not the owning
  view hierarchy.
- Place a dialog and its orchestration service under a feature only when it is feature-specific.
  When used across application areas, keep both in `shared` and leave feature-specific transport
  subscriptions and filtering in the consuming feature.
- Keep root and layout components free of aggregation- or leaf-specific state they only relay; keep
  it in the owning lower component or an existing feature state service.
- In shared action services, track in-flight state for the whole service or per action identity,
  not with one boolean per concrete action.
- Name boolean properties, signals and inputs as predicates (`is`, `has`, `can`, `should` or
  similar), such as `isDisabled`.
- When the backend already provides or enforces an availability or eligibility rule, do not
  duplicate it in a frontend validator; validate only client-side state the backend does not
  represent.
