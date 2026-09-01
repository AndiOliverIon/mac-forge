# Unit-Test Execution Requires Oliver's Approval

- Never run frontend or backend unit tests unless Oliver explicitly authorizes that specific run.
- When unit tests are recommended, tell Oliver which tests should be run and why, then wait for his decision.
- A request to implement, review, validate, check a commit, or prepare/process a review handoff does not authorize unit-test execution.
- This restriction applies to Artanis and Argus, including targeted tests, full suites, coverage runs, watch-mode runs, and tests launched through IDEs, build scripts, or other wrappers.
- Non-test checks such as compilation, type-checking, linting, formatting verification, and production builds remain allowed when relevant to the requested task.
- In review requests and findings, state unit tests as `not run — awaiting Oliver's explicit authorization` unless Oliver authorized and the agent completed that specific run.
