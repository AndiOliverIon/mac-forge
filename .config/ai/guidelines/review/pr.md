# PR Review of a Peer's Work

Apply when Oliver asks for a review “for PR” (for example “Review last 3 commits for PR”, “Review
this branch for PR against develop”). The author is a human colleague; Oliver posts the comments
himself. This is not a handoff: write no transporter files.

## Target

- “Last N commits”: `HEAD~N..HEAD` on the current branch of the repository in scope.
- “This branch”: `$(git merge-base <base> HEAD)..HEAD`; `<base>` is the one Oliver names, otherwise
  the repository's default branch. If the default cannot be determined, ask.
- Rerun the resolver with `--mode pr-review --review-target <range>` and load every emitted batch.
- Before reviewing, check that the range belongs to the PR: report a merge commit, commits already
  on the base, or mixed authors in one line instead of silently reviewing them.

## Boundaries

- Read-only: no fixes, commits, PR comments, or remote calls unless Oliver asks.
- Review the diff in the context of the changed files. Raise an issue outside the diff only when it
  directly breaks the changed code.
- Jira stays dormant unless Oliver names a task key in the request.

## Validation

- Scope linting, formatting, and similar validation to files changed by the review target whenever
  the underlying tool accepts file paths. Run repository-wide checks only when scoped execution is
  unavailable, project configuration requires full context, or Oliver explicitly requests them.
  Stop a non-essential repository-wide check after 60 seconds without progress when an equivalent
  scoped check is available.

## Output

Answer in the conversation, all problems in one response, ordered by severity (`blocking`,
`should-fix`, `nit`). Report every verified problem unless Oliver asks for a top N. Do not number
low-confidence suspicions; list them on one closing `Worth asking:` line.

```md
**PR review** — `<range>` · <N> commits by <author(s)> · <P> problems (<b> blocking, <s> should-fix, <n> nit)

### Problem 1/<P> — <severity>
**File:** `<path>:<line or range>`
**Problem:** <what is wrong and the evidence, one or two sentences>
**Recommendation:** <the concrete fix, one or two sentences>
**Reply to author:**
> <comment ready to paste>
```

- Line numbers refer to the new file, as the PR diff shows them; for a removed line write
  `removed, old line <n>`.
- Recommendation is for Oliver and may cite guideline sources.
- Reply to author is in Oliver's voice: polite, specific, short, phrased as a question when the
  problem is uncertain, with no mention of AI and no internal guideline references.
- Close with one verdict line (`ready to merge`, `merge after fixes`, or `needs discussion`) and
  `Tests: not run — awaiting Oliver's explicit authorization` unless he authorized a run.
- With no problems, write `No problems found` and state what was inspected.

## Follow-ups

Without re-reviewing: “Expand problem <k>” explains it in detail; “Rewrite reply <k> softer” or
“…shorter” changes only that reply; “Suggest code for problem <k>” adds a ```` ```suggestion ````
block for the PR comment.
