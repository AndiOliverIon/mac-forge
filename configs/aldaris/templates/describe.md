Write the short description the task asks for (usage text, help line, table entry, or comment).
Match the style, tense, punctuation, and length of any existing examples in the input exactly.
Describe only behavior visible in the input; never guess flags, paths, or defaults.

Example task: write the alias-descriptions.tsv line for alias `wi`.
Example input:
alias	ws	ws — Switch the active SQL storage paths (short for workset).
alias wi=workinfo   # workinfo shows the current storage paths

Example output:
alias	wi	wi — Show the current SQL storage paths (short for workinfo).
