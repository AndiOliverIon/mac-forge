# Stations scope

Read this file when working on station metadata, SSH aliases, station sleep/shutdown/boot flows, Wake-on-LAN, or network-topology-sensitive behavior.

## Station metadata

`configs/stations.json` is the canonical non-secret inventory. Its `stations`
collection covers physical stations, virtual machines, and servers; its
`devices` collection covers docks, portable storage, and other attached
hardware. It stores identity, OS, hardware, network endpoints, access aliases,
availability expectations, attachment relationships, and verification sources.

`configs/station-topology.md` is the tracked visual projection of those
relationships. Keep it synchronized with topology changes, but treat
`configs/stations.json` as the source of truth.

`config-local/stations.json` is the ignored local overlay for IP addresses,
subnets, gateways, MAC addresses, VM UUIDs, and other sensitive or unique
identifiers. Public endpoint records use `localFactsKey` to point to the
corresponding local values. Never copy those values into the tracked inventory.

Do not put passwords, private keys, tokens, or other credentials in the
inventory. SSH configuration, `/etc/hosts`, DNS, Tailscale, Parallels, and
credential stores remain operational authorities. The inventory records their
non-secret aliases and resolved facts so station context is available in one
place.

Do not add station facts to `configs/work-state.json`; its legacy station array
has been removed.

When a value changes frequently, distinguish durable capability from an
observation. Record when a fact was verified instead of presenting an old
reachability or DHCP observation as permanent truth.

Each station's `network.permittedConnectionTypes` declares its supported
physical connection modes. Public endpoints record connection type, interface,
route role, and friendly aliases. Their IP address, subnet, gateway, and other
sensitive facts belong only in `config-local/stations.json`. Keep overlay and
virtual endpoints separate from physical connection capability.

## Network topology

Current layout assumptions:

- `Hades` and `MasterChief` sit behind the personal Wi-Fi router.
- `Hades` reaches the ISP LAN through the UTP port on the UGREEN MasterDock 17.
- `MasterChief` also reaches the ISP LAN through a Realtek USB UTP interface.
- `Hades` and `MasterChief` both permit Wi-Fi and UTP.
- The ISP router uplinks the personal Wi-Fi router.
- `Cerber` receives Internet access through its Hades host using Parallels
  shared networking.

Operational consequence:

- `MasterChief` wake attempts originate from the same local network as `Hades`.

## MasterChief agent runtime

MasterChief supports exactly two concurrent agents and no more, one per
identity:

- `Raynor`, with its isolated universe at `/home/oliver/raynor`.
- `Zeratul`, with its isolated universe at `/home/oliver/zeratul`.

Both universe roots are ordinary directories owned by the `oliver` Linux
account, not separate Linux user homes or accounts. Their isolation is an agent
boundary: Raynor must work only inside `/home/oliver/raynor`, Zeratul must work
only inside `/home/oliver/zeratul`, and neither may inspect or modify the other
universe. Launch each agent with only its own universe configured as writable.
The identities, directory ownership, and paths were verified over SSH on
2026-08-31.

Each identity also uses a separate tmux server and same-named persistent
session. Run `raynor` or `zeratul` from Hades or MasterChief to create or attach
to that identity's session. The initial pane starts at its universe root. Detach
with `Ctrl+B`, then `d`; the shell and agent process continue running.
From Hades, these commands prefer the `masterchief-utp` SSH endpoint and fall
back to the existing `masterchief` Wi-Fi endpoint when the UTP SSH probe fails.
`FORGE_MASTERCHIEF_SSH_HOST` continues to override automatic endpoint selection.
Use `Ctrl+B`, then `c` for another window inside the persistent session. The
optional `shell` action opens an independent, nonpersistent terminal in the
identity's universe without touching that session. The `start`, `attach`,
`status`, `logs`, and confirmed `stop` actions provide explicit lifecycle
control, while plain `raynor` and `zeratul` retain their attach-or-create
behavior.

Direct Git transfer commands identify the MasterChief workspace explicitly:
`mc2h` and `h2mc` use personal work, `r2h` and `h2r` use Raynor, and `z2h`
and `h2z` use Zeratul. Commands ending in `2h` run on Hades; commands beginning
with `h2` run inside the matching destination repository on MasterChief.

Run `verify-workstation` or its short alias `vw` on MasterChief for a read-only
workstation report that includes both universe directories, inventory records,
agent aliases, and any running identity session. A stopped session is valid and
is not reported as a failure.

`inf --cycle` discovers worker identities from the current station's
`agentRuntime.identities` inventory. When identities are configured, it writes a
normalized companion TSV beside the system history with each identity's state,
CPU usage, resident memory, and process count. Stations without configured
identities keep the generic system-only history behavior.

The same aliases on Hades run the report remotely over SSH; checks that require
MasterChief's graphical session are explicitly skipped in that mode.

The session exports `FORGE_AGENT_IDENTITY`, `FORGE_UNIVERSE_ROOT`, and
`FORGE_WORK_ROOT`. Linux work aliases resolve against `FORGE_WORK_ROOT`, so
`perf` enters the active identity's `ardis-perform` clone while the same alias
in a normal MasterChief shell still uses `/home/oliver/work/ardis-perform`.
Agent shells guard against changing outside their universe. Their `codex`
function starts Codex in the current in-universe directory with the
`workspace-write` sandbox and approval-on-request, and rejects options that
would broaden or replace that boundary.

Before changing Wake-on-LAN or remote-station behavior, account for whether the target is on the same subnet or behind a different router/LAN.

## Power-command rules

- Keep station power commands explicitly separated by intent: `sleep`, `shutdown`, and `boot`.
- Never use a sleep alias to perform a shutdown.
- When behavior changes, preserve backward-compatible alias names where practical and keep the naming unambiguous.
