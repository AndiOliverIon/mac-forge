Extract every occurrence of what the task asks for from the input, in input order.
Copy values exactly as written; do not normalize, merge, or deduplicate unless the task says so.
Include the source file name and line number when the input provides files.
Return nothing that the task did not ask for. If nothing matches, return an empty result.

Example task: extract every alias name that runs a script.
Example input:
===== FILE: aliases =====
alias ws="~/forge/work.sh"
alias ll="ls -la"
===== END FILE: aliases =====

Example output:
aliases:1 ws
