# Provisional Angular Rules

- Reserve `views` for route entry, landing, and page-level components. Place components rendered
  inside those views under the corresponding `features/<domain>` area, and name them for the domain
  content or role they render rather than repeating the owning view hierarchy.
- When a backend endpoint already provides or enforces an availability or eligibility rule, do not
  duplicate that rule in a frontend validator. Keep only checks for client-side state the backend
  does not represent.
- Keep root and layout components free of aggregation- or leaf-specific state that they only relay
  to another consumer. Keep that state in the owning lower component or an existing feature state
  service.
- Name boolean properties, signals, and inputs as predicates with an `is`, `has`, `can`, `should`,
  or equivalent intent-revealing prefix, such as `isDisabled` or `isEnabled`.
- In shared action services, represent in-flight state generically for the whole service or by
  action identity rather than adding a boolean for each concrete action.
