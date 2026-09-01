# Artanis–Argus Review Handoff Router

This file is the single entry point for the persistent Artanis–Argus review handoff. The protocol is dormant unless Oliver invokes a handoff command or an unambiguous natural-language equivalent.

## Route Before Acting

When a handoff trigger is invoked:

1. Determine the physical station from the local hostname. Normalize it to lowercase and compare its short hostname with the canonical station identifiers.
2. Load `~/.config/ai/guidelines/handoff/common.md` completely.
3. Load exactly one station flow completely:
   - `masterchief` -> `~/.config/ai/guidelines/handoff/masterchief.md`
   - `hades` -> `~/.config/ai/guidelines/handoff/hades.md`
4. Resolve the active lane using that station flow before reading or writing transporter files.
5. Follow the common protocol and the selected station flow together. The station flow controls lane discovery, paths, identity fields, and isolation; the common protocol controls roles, ownership, review behavior, and document structure.

Station routing has precedence over path-based guesses. Never select the Hades flow merely because a MasterChief path is unavailable, and never select the MasterChief flow merely because a similarly named directory exists on Hades.

If the hostname is unknown, matches more than one station, or cannot be determined safely, stop and ask Oliver which station flow to use. Do not default to either flow and do not inspect or modify transporter files.

Loading this router alone does not authorize creating a lane, writing a request, processing a review, analyzing findings, or changing repository files. Those actions require their corresponding handoff trigger and the authorization boundaries in the common protocol.
