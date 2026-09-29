Summarize each input item in exactly one line, in the order given.
Format each line as `<name>: <summary>`, where <name> is the file name or item label.
Each summary states what the item does, in present tense, under 20 words, with no marketing words.
Use only facts visible in the input.

Example input:
===== FILE: scripts/backup.sh =====
#!/usr/bin/env bash
tar -czf "/backups/$(date +%F).tgz" ~/data
===== END FILE: scripts/backup.sh =====

Example output:
backup.sh: Archives ~/data into a date-stamped tarball under /backups.
