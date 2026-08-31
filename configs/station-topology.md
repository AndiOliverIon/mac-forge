# Station and device topology

This is the tracked visual view of `configs/stations.json`. Keep the JSON
inventory canonical and update this document when its relationships change.
Sensitive addresses and identifiers remain in `config-local/stations.json` and
must not be copied here.

Solid lines are usual or active paths. Dashed lines are on-demand or portable
paths.

## Physical and display topology

```mermaid
flowchart TB
    Hades["Hades<br/>MacBook Pro · macOS"]
    MasterChief["MasterChief<br/>Dell Precision · Ubuntu"]
    Charon["Charon<br/>iPad Pro 13-inch M5"]
    Cerber["Cerber<br/>Windows 11 VM"]

    Dock["UGREEN MasterDock 17"]
    DockNVMe["Internal Samsung 990 Pro<br/>2 TB"]
    Acasis["Acasis portable NVMe<br/>2 TB"]
    MSI["MSI MPG321UX OLED<br/>4K · 180 Hz"]
    Dell["Dell U3223QE<br/>4K · 60 Hz"]

    Hades -->|"USB4 v2 · 80 Gb/s"| Dock
    Hades -->|"Parallels"| Cerber

    Dock -->|"Internal NVMe"| DockNVMe
    Dock -->|"Thunderbolt 3 · 40 Gb/s"| Acasis
    Dock -->|"USB / CoreDevice"| Charon
    Dock -->|"USB-C"| MSI
    Dock -->|"DisplayPort · usual input"| Dell

    MasterChief -. "USB-C · alternate input" .-> Dell
    Acasis -. "Portable when needed" .-> MasterChief
    Acasis -. "Portable when needed" .-> Charon
```

## Internet paths

Hades receives its wired connection through the UGREEN dock. MasterChief also
has a direct UTP connection to the ISP wired LAN. Cerber uses Hades as its
upstream host.

```mermaid
flowchart TB
    Internet["Internet"]
    ISP["ISP wired LAN"]
    WiFi["Personal Wi-Fi LAN"]
    Dock["UGREEN MasterDock 17"]
    Hades["Hades"]
    MasterChief["MasterChief"]
    Cerber["Cerber"]
    VPS1["vps1"]

    Internet --> ISP
    Internet --> VPS1
    ISP --> WiFi
    ISP -->|"UTP"| Dock
    ISP -->|"UTP"| MasterChief
    Dock -->|"Ethernet over USB4"| Hades
    Hades -->|"Parallels shared networking"| Cerber
```

## Wi-Fi membership

This is a separate tree so each station has a direct, non-intersecting branch.

```mermaid
flowchart TB
    WiFi["Personal Wi-Fi LAN"]
    Hades["Hades"]
    MasterChief["MasterChief"]
    Charon["Charon"]

    WiFi -->|"Wi-Fi"| Hades
    WiFi -->|"Wi-Fi"| MasterChief
    WiFi -->|"Wi-Fi"| Charon
```
