# Provisional Angular Rules

- Reserve `views` for route entry, landing, and page-level components. Place components rendered
  inside those views under the corresponding `features/<domain>` area, and name them for the domain
  content or role they render rather than repeating the owning view hierarchy.
- When a backend endpoint already provides or enforces an availability or eligibility rule, do not
  duplicate that rule in a frontend validator. Keep only checks for client-side state the backend
  does not represent.
