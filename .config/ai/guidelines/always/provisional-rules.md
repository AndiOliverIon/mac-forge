# Provisional Rule Lifecycle

- Human review feedback is evidence, not automatically a rule. When Oliver asks whether feedback is
  valuable as provisional guidance, compare it with sealed and provisional guidance, relevant code,
  and established conventions. Recommend yes or no; for yes, propose the exact rule and its general,
  Angular, .NET, or SQL chapter.
- Do not write a rule until Oliver explicitly confirms it after that recommendation. If rejected,
  write nothing. If the proposal conflicts with existing guidance, debate and resolve the conflict
  before admission.
- On confirmation, add one concise, non-duplicative rule to the selected file under
  `~/.config/ai/guidelines/provisional/`. Registering the rule includes committing and pushing the
  Mac Forge change under its Git policy.
- An admitted provisional rule is immediately mandatory within its chapter. "Provisional" describes
  its maturity, not its enforcement strength.
- A provisional rule has only two eventual outcomes: delete it when it proves inconsistent or
  valueless, or promote it into the corresponding sealed guidance and remove the provisional entry
  in the same change. For Angular promotion, keep development and review guidance synchronized.
- Git history is the only record required for removed rules. Artanis, Argus, and Aegis may recommend
  candidates, but none may admit, remove, or promote one without Oliver's explicit decision.
