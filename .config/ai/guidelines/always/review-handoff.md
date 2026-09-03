# Artanis–Argus Review Handoff Router

The protocol is dormant unless Oliver invokes a handoff command or an unambiguous equivalent.

## Route Before Acting

1. Derive the physical station only from the normalized lowercase short hostname:
   - `masterchief` → `~/.config/ai/guidelines/handoff/masterchief.md`
   - `hades` → `~/.config/ai/guidelines/handoff/hades.md`
2. If the hostname is unknown, ambiguous, or unsafe to determine, stop and ask Oliver. Do not choose
   a flow or inspect or modify transporter files.
3. Load `~/.config/ai/guidelines/handoff/common.md` and exactly one mapped station flow completely.
4. Resolve the active lane through that station flow before touching transporter files. Station
   identity overrides path-based guesses.
5. Apply both files: the station flow owns lane discovery, paths, identity, and isolation; the common
   protocol owns roles, file ownership, review behavior, and document structure.

Loading this router alone authorizes no lane creation, transporter write, review processing, findings
analysis, or repository change. Each action requires its trigger and the common protocol's boundary.
