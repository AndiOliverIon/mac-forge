# Provisional General Rules

- Do not widen a shared method with parameters or branches for one consumer's special case. Give
  that consumer a dedicated method that the shared method neither knows about nor dispatches to.
- When a lookup finds no valid target, fail with the established error. Add no fallback selection
  (history, defaults, newest or closest match) unless the contract defines it.
