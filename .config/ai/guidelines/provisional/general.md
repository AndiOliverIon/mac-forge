# Provisional General Rules

- Do not widen a shared method with a parameter or branch that serves one consumer's special case.
  Add a dedicated method called only by that consumer; the shared method must neither know about nor
  dispatch to it.
- When a lookup finds no valid target, fail with the established error. Do not add fallback
  selection (historical records, defaults, newest or closest match) unless the contract defines it.
