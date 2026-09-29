# Aldaris Delegation

Aldaris is a local Ollama text helper on Hades, not a team identity: it never reviews or edits files,
and you stay accountable for every result you use.

- Allowed by default for the callers in `~/mac-forge/configs/aldaris/config.json`, whose `maxLevel`
  only Oliver changes. Skip it for any task where Oliver's prompt excludes it.
- Delegate only steps you are highly confident it handles; when in doubt, do it yourself. Fits:
  summarizing, extracting, reformatting, sorting, boilerplate, one-line descriptions. Never reviews,
  findings, security or destructive decisions, database changes, secrets, or anything requiring
  repository rules.
- Rate each step honestly as `trivial`, `standard`, `moderate`, or `high`; never downgrade it to pass
  the limit.
- Call `~/mac-forge/scripts/aldaris-ask.sh` (options in `--help`). Prefer a template, a schema when
  you will parse the result, and excerpts over whole files. If it fails, Ollama is offline, or Aldaris
  declines, do the step yourself, say so in one line, and continue; never start Ollama.
- Reproduce every call in your reply as a `⚡ ALDARIS DELEGATION` block: id, when, level, request,
  response (trimmed only with the omission stated), and duration.
- Use the response without re-verifying it. Flag problems that surface with `--verdict <id>
  corrected|rejected`, and list used ids in review requests so reviewers can flag outputs behind
  findings.
