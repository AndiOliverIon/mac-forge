# Stations scope

Read this file when working on station metadata, SSH aliases, station sleep/shutdown/boot flows, Wake-on-LAN, or network-topology-sensitive behavior.

## Station metadata

`configs/work-state.json` contains a top-level `stations` array used as the machine inventory for remote stations.

Each station record currently stores:

- `name`
- `ip`
- `mac`
- `os`

Current examples in repo state:

- `MasterChief` -> `192.168.68.115`, `C4:03:A8:37:38:81`, `Windows`
- `Thanatos` -> `192.168.100.46`, `E8:9C:25:38:4C:63`, `Windows`

Prefer reading this data from `configs/work-state.json` instead of hardcoding duplicates.

## Network topology

Current layout assumptions:

- `Hades` and `MasterChief` sit behind the personal Wi-Fi router on the `192.168.68.x` network.
- `Thanatos` sits on a different LAN exposed directly from the ISP router on `192.168.100.x`.
- The ISP router uplinks the personal Wi-Fi router and separately connects `Thanatos`.

Operational consequence:

- `MasterChief` wake attempts originate from the same local network as `Hades`.
- `Thanatos` wake attempts originate across routers and subnets, so broadcast-based Wake-on-LAN is less reliable unless relayed from within the `192.168.100.x` network.

Before changing Wake-on-LAN or remote-station behavior, account for whether the target is on the same subnet or behind a different router/LAN.

## Power-command rules

- Keep station power commands explicitly separated by intent: `sleep`, `shutdown`, and `boot`.
- Never use a sleep alias to perform a shutdown.
- When behavior changes, preserve backward-compatible alias names where practical and keep the naming unambiguous.
