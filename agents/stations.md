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
- `Hades` permits both Wi-Fi and UTP; `MasterChief` currently permits Wi-Fi only.
- The ISP router uplinks the personal Wi-Fi router.
- `Cerber` receives Internet access through its Hades host using Parallels
  shared networking.

Operational consequence:

- `MasterChief` wake attempts originate from the same local network as `Hades`.

Before changing Wake-on-LAN or remote-station behavior, account for whether the target is on the same subnet or behind a different router/LAN.

## Power-command rules

- Keep station power commands explicitly separated by intent: `sleep`, `shutdown`, and `boot`.
- Never use a sleep alias to perform a shutdown.
- When behavior changes, preserve backward-compatible alias names where practical and keep the naming unambiguous.
