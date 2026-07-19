# CodeMeter / WIBU / ARDIS License Architecture

Last verified: 2026-07-17

This is the source of truth for the ARDIS CodeMeter license setup shared by
macOS, Windows, Linux, and containerized applications. The license holder is
`vps1`; development machines are clients and reach it only through an
on-demand SSH tunnel.

Do not install or activate the CmCloud credential on every workstation. Do not
create a second license holder unless this architecture is intentionally being
migrated.

## Architecture

```text
WIBU CmCloud
    ^
    | outbound Internet connection
    |
vps1 (CodeMeter Lite, CmCloud credential and activated ARDIS licenses)
    ^
    | SSH local forwarding; remote endpoint 127.0.0.1:22350
    |
Mac or Linux workstation
    |-- native/local client -> 127.0.0.1:22350
    |-- Docker client       -> host.docker.internal:22350
    `-- Windows CERBER      -> 10.211.55.2:22350 (Parallels private bridge)
```

There is no Tailscale dependency and no permanent CodeMeter Docker sidecar.
CodeMeter is deliberately not exposed on the public network. The workstation
opens the license tunnel only when a licensed application needs it.

## Current validation state

Completed and verified on 2026-07-17:

- The credential and all seven WebDepot items are activated on `vps1`.
- `vps1` can connect to WIBU CmCloud and lists the expected container/content.
- `vps1` publishes all seven ARDIS products as network licenses.
- The on-demand tunnel reaches `vps1` from Mac loopback.
- The tunnel's private Parallels listener is reachable at `10.211.55.2:22350`.
- Windows `CERBER` returned `TcpTestSucceeded: True` for that address.
- CodeMeter Runtime 8.40a is installed and running inside Windows `CERBER`.
- `10.211.55.2` is configured in CERBER's CodeMeter Server Search List.
- CERBER's `cmu --list-network` enumerates Firm Code `6001576`, all seven
  products, and their correct free-seat counts through the SSH tunnel.
- OPTIMIZER's active configuration was changed from local-only lookup
  (`KeyLocal=1`) to network lookup (`KeyLocal=0`).
- The obsolete `MasterChief` and `255.255.255.255` search-list entries were
  removed. The only explicit registry server is now
  `Server1 = 10.211.55.2`.

Still to be completed:

- Resolve OPTIMIZER's application-level license lookup. The key remains
  red-crossed and COWIN remains `Used=0 Free=6` even though CERBER's `cmu`
  enumerates the same license successfully.
- Validate PERFORM separately if licensing is enabled for it in the future.

The transport and CodeMeter network-license path are proven. End-to-end
application validation is not complete until OPTIMIZER checks out a COWIN
seat and the server changes from `Used=0 Free=6` to `Used=1 Free=5`.

## Authoritative identities

| Item | Value |
| --- | --- |
| License vendor | ARDIS Information Systems NV |
| WIBU Firm Code | `6001576` |
| Hosting type | CmCloudContainer / cloud hosting |
| WebDepot container number | `140-560129638` |
| Full `cmu` container serial | `140-560129638-1439315497` |
| ARDIS/WIBU identity | `15527_18864` |
| License ID | `15527` |
| Holder | `vps1` |
| CodeMeter protocol port | `22350` |
| CodeMeter WebAdmin port | `22352` |

The credential archive and its `.wbc` file are secrets/recovery material. Keep
the original archive in the encrypted vault. Do not commit it, copy it into
this repository, email it, or import it into client machines.

## Activated license inventory

All WebDepot items were activated on 2026-07-17 at 14:02:10 against
CmContainer `140-560129638`.

| Product | Product Code | Quantity | Notes |
| --- | ---: | ---: | --- |
| COWIN | `1` | 6 | Network capable |
| PRINT | `5` | 2 | |
| ASMS2 | `7` | 5 | |
| APO | `8` | 2 | 120-second linger |
| AxProtector | `12` | 1 | |
| PERFORM | `13` | 2 | 120-second linger |
| ARDIS internal ID item | `99` | — | Internal key identity |

The container advertises CodeMeter network licensing capabilities including
station sharing, exclusive use, and user-limit modes. Actual application
concurrency remains governed by the individual product entitlements above.

## Machine roles

### `vps1`: the only license holder

- Ubuntu 24.04.4 LTS, x86_64.
- Reachable through SSH host alias `vps1` (`152.53.45.162` at the time this
  document was written).
- Runs official WIBU CodeMeter Lite 9.00 Driver Only.
- Debian package: `codemeter-lite`, version `9.0.8031.500`.
- Installed package SHA-256:
  `3f39de56b9980c8d07992ab765fd101d7086759fbc03317ba9fada7bad121394`.
- `codemeter.service` is enabled and active.
- Holds the imported CmCloud credential and all activated ARDIS licenses.
- Requires continuous outbound Internet access and correct system time.

Relevant `/etc/wibu/CodeMeter/Server.ini` state:

```ini
[General]
BindAddress=127.0.0.1
IsNetworkServer=1
NetworkPort=22350

[HTTP]
RemoteRead=0
Port=22352
```

Network-server mode must be enabled or CodeMeter accepts a TCP connection but
does not publish the licenses to clients. `BindAddress=127.0.0.1` keeps the
network server private despite `IsNetworkServer=1`. The verified listeners are
`127.0.0.1:22350`, `[::1]:22350`, and `127.0.0.1:22352`; SSH terminates on
`vps1` and connects to the IPv4 loopback listener. Do not change the bind
address to `0.0.0.0` merely to make a client work.

### macOS workstation

The Mac is a tunnel controller, not a license holder. This architecture does
not require CodeMeter Runtime on macOS.

The shared implementation is:

- `scripts/vps1/vps1-license-tunnel.sh`
- `dotfiles/aliases-vps1`
- `configs/alias-descriptions.tsv`

The tunnel listens on:

- `127.0.0.1:22350` for native applications and Docker host forwarding.
- The detected Parallels `bridge100` address, currently
  `10.211.55.2:22350`, for the Windows VM.

The Parallels listener is bound only to its private bridge, not to Wi-Fi,
Ethernet, or all interfaces.

### Windows VM `CERBER`

- Parallels VM name: `Windows 11`.
- Guest hostname: `CERBER`.
- Windows 11 Pro, ARM64.
- Shared-network guest address: `10.211.55.3`.
- macOS Parallels bridge address: `10.211.55.2`.
- Runs ARDIS OPTIMIZER 6.4.2 / COWIN.

OPTIMIZER currently identifies:

- License ID `15527`.
- License definition `C:\Ardis\15527.DEF`.
- Installed source license file `C:\Ardis\15527.alx`.
- Accepted keys `WID:15527_16314;PC:1;WID:15527_18864`.

`WID:15527_18864;PC:1` matches the new CmCloud identity and its COWIN
entitlement exactly.

The Windows VM needs a local CodeMeter Runtime because OPTIMIZER talks to that
client runtime, and the runtime searches the network server. It does not need
the cloud credential. ARDIS recommends CodeMeter Runtime 8.40a for this
OPTIMIZER generation:

- Setup page: <https://www.ardis.eu/de-DE/setup>
- Runtime installer:
  <https://download.ardis.be/tools/CodeMeterRuntime_8.40a.exe>
- OPTIMIZER downloads: <https://download.ardis.be/OPTIMIZER/>

After installing the runtime as administrator:

1. Open CodeMeter WebAdmin at <http://localhost:22352>.
2. Open **Configuration > Basic > Server Search List**.
3. Add `10.211.55.2`.
4. Apply the setting and restart the Windows CodeMeter service.
5. Keep only **WIBU CodeMeter** selected in OPTIMIZER's key dialog.
6. Ensure the active OPTIMIZER profile has `[PREFERENCES] KeyLocal=0`.
7. Refresh/reopen OPTIMIZER while the Mac tunnel is up.

The vendor-provided `15527.alx`, when required, belongs in `C:\Ardis` and is
selected by OPTIMIZER. It is a license-definition/configuration file, not the
CmCloud credential. Do not substitute it for the `.wbc` credential or import
the `.wbc` into Windows.

#### OPTIMIZER local versus network lookup

CodeMeter's Server Search List does not override OPTIMIZER's own local-key
preference. In OPTIMIZER 6.4.2, a failed popup showing `(LOCAL)` and
`CmContainer Entry not found, Error 200` can occur even while `cmu` lists all
remote licenses correctly.

The controlling value is stored separately in each active `OPTIMIZER.ini`:

```ini
[PREFERENCES]
KeyLocal=0
```

- `KeyLocal=1`: search only the Windows machine; the tunnel/server is ignored.
- `KeyLocal=0`: allow the CodeMeter network-server lookup.

ARDIS documentation describes this as choosing whether the key is **on this
computer** or **on another**. The 6.4.2 key dialog used on CERBER displays only
the WIBU checkbox and does not expose that choice, so the INI value may need to
be corrected directly while OPTIMIZER is fully closed.

The active profile discovered during validation was:

```text
C:\Users\oliver\.AD\C\ArdisHQ\Demo-1 Local Prod. Batching\OPTI\OPTIMIZER.ini
```

It originally contained `KeyLocal=1` and was changed to `KeyLocal=0`, with a
backup created before the edit.

#### Ardis Demo Tools configuration root

`Ardis Demo Tools` manages the configuration hierarchy rooted at:

```text
C:\Users\oliver\.AD\C
```

Its role is to configure PERFORM and OPTIMIZER together in different
combinations. Each configuration below this root has its own `OPTIMIZER.ini`;
changing `KeyLocal` in one configuration does not update the others.

**Whenever Ardis Demo Tools switches to another configuration, verify that the
new configuration's own `[PREFERENCES]` section contains `KeyLocal=0`.**
Otherwise OPTIMIZER returns to `(LOCAL)` lookup and shows a red-crossed key even
though CodeMeter, the SSH tunnel, and `vps1` are working correctly.

Inventory the setting in every Demo Tools configuration from CERBER
PowerShell:

```powershell
Get-ChildItem 'C:\Users\oliver\.AD\C' -Filter OPTIMIZER.ini -Recurse |
    Select-String -Pattern '^KeyLocal='
```

Close every OPTIMIZER instance before editing an INI, and back up each target
file first. Prefer changing only the active configuration instead of blindly
rewriting every Demo Tools profile.

#### Unresolved OPTIMIZER 6.4.2 checkout

As of 2026-07-17, the following has been proven:

- The active INI contains `[PREFERENCES] KeyLocal=0`.
- The same INI contains `[Sentinel] Type=W`, selecting WIBU.
- The live process command is:

  ```text
  "C:\ARDIS\COWIN.EXE" /INI="C:\Users\oliver\.AD\C\ArdisHQ\Demo-1 Local Prod. Batching\OPTI\OPTIMIZER.ini"
  ```

- Ardis Demo Tools does not add a command-line local-key override.
- `C:\ARDIS\COWINLIBu.dll` is version `6.4.2.0`.
- The 32-bit client DLL used by this application is
  `C:\Windows\SysWOW64\WibuCm32.dll`, CodeMeter 8.40a build 7120.
- CERBER's effective CodeMeter registry has only the explicit server
  `10.211.55.2`. The registry still reports `UseBroadcast=1`, even though the
  visible automatic-search entry was removed.
- `cmu --list-network --server 10.211.55.2 --firmcode 6001576` succeeds from
  CERBER and lists COWIN Product Code `1`, six free seats, and key identity
  `15527_18864`.
- OPTIMIZER still shows a red-crossed key and does not allocate a COWIN seat.
- The CodeMeter Windows event provider recorded service lifecycle events but
  no observable COWIN allocation event during this failed attempt.

This means the proven failure boundary is now inside OPTIMIZER/COWINLIBu's
application-level lookup, not the CmCloud credential, `vps1`, SSH tunnel,
Windows CodeMeter Runtime, or CodeMeter network inventory.

There is also a material compatibility risk: CERBER is Windows 11 ARM64 under
Parallels, while ARDIS's published OPTIMIZER requirements say ARM processors
are not supported. OPTIMIZER and its x86 licensing wrapper run through Windows
emulation, but successful CodeMeter enumeration by `cmu` does not prove that
the older COWIN licensing wrapper works correctly under that emulation.

- Requirements: <https://download.ardis.be/OPTIMIZER/system-requirements.htm>

Do not label ARM64 as the confirmed cause without a comparison test. The
cleanest discriminator is running the same license definition and network
server against OPTIMIZER on a supported Intel/AMD Windows installation, or
obtaining confirmation/a compatible build from ARDIS support.

### Linux workstation

The same script and aliases are designed to work on a second Linux development
machine:

- Clone/bootstrap `mac-forge`.
- Ensure the shared `dotfiles/aliases-vps1` is sourced.
- Configure key-based SSH access through the `vps1` host alias.
- Required tools are Bash, OpenSSH client, `lsof`, and netcat
  (`netcat-openbsd` on Debian/Ubuntu).
- Point a native CodeMeter client at `127.0.0.1` while the tunnel is up.

Parallels bridge auto-detection runs only on macOS. A Linux workstation gets
the loopback listener unless `LICENSE_PARALLELS_BIND` is explicitly configured.

### Perform and Docker

Perform is not the primary validation client because it can currently run
without licensing. Its intended licensed path is:

```text
Perform container
  -> host.docker.internal:22350
  -> workstation SSH tunnel
  -> vps1 127.0.0.1:22350
  -> CmCloud
```

Existing application configuration uses `ARDIS_LICENSE_SERVER` /
`CODEMETER_HOST`, normally with `host.docker.internal`. Docker is only the
application's runtime boundary; it is not another license server.

Do not run the downloaded amd64 CodeMeter Debian package under Apple Silicon
Docker emulation. Testing showed `CodeMeterLin` terminating with
`Illegal instruction`. If a temporary native-container diagnostic is ever
needed, WIBU's multi-architecture `wibusystems/codemeter` image is the suitable
starting point, but it is not part of the production architecture.

## Daily operation

Open a new shell after bootstrapping/pulling `mac-forge`, or source the aliases:

```bash
source ~/mac-forge/dotfiles/aliases-vps1
```

Start, inspect, and stop the license path:

```bash
v1-license-tunnel-up
v1-license-tunnel-status
v1-license-tunnel-down
```

The tunnel is idempotent. On macOS it also adds the private Parallels listener
when `bridge100` exists. Stop it when licensed software is no longer needed.

Supported overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `VPS1_SSH_HOST` | `vps1` | SSH destination |
| `LICENSE_LOCAL_PORT` | `22350` | Workstation listening port |
| `LICENSE_REMOTE` | `127.0.0.1:22350` | Endpoint on `vps1` |
| `LICENSE_LOCAL_BIND` | `127.0.0.1` | Native/local bind address |
| `LICENSE_PARALLELS_BIND` | `auto` | Auto-detect, explicit address, or `off` |

## Verification

### On `vps1`

```bash
systemctl is-active codemeter
systemctl is-enabled codemeter
cmu --verify-cloud-connection
cmu --list
cmu --list-content --serial 140-560129638-1439315497
ss -ltnp | grep -E ':22350|:22352'
```

Expected essentials:

- Service is active and enabled.
- Cloud test reaches `https://eu-backend.wibu.cloud/test`.
- Exactly one enabled CmCloud container is listed.
- Firm Code `6001576` and the expected product codes are present.
- CodeMeter listens only on `vps1` loopback.

### On macOS or Linux

```bash
v1-license-tunnel-status
nc -zv 127.0.0.1 22350
```

### In Windows `CERBER`

With the Mac tunnel up:

```powershell
Test-NetConnection 10.211.55.2 -Port 22350

$cmu = @(
  "$env:ProgramFiles\CodeMeter\Runtime\bin\cmu.exe",
  "${env:ProgramFiles(x86)}\CodeMeter\Runtime\bin\cmu.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

& $cmu --list-server
& $cmu --list-network --server 10.211.55.2 --firmcode 6001576
```

`TcpTestSucceeded` must be `True`. The network listing must return serial
`140-560129638`, Firm Code `6001576`, and the expected Product Codes.

The main CodeMeter Control Center license list can remain empty because it
primarily displays locally connected containers. For this architecture,
`cmu --list-network` is the definitive CERBER-to-`vps1` enumeration test.
OPTIMIZER should then accept `WID:15527_18864;PC:1` when its active profile has
`KeyLocal=0`.

## Initial activation record

This is the successful sequence, preserved for a rebuild:

1. Select **Cloud hosting** in ARDIS WebDepot. This is the correct choice for a
   virtual server with continuous Internet access. Digital/CmAct is intended
   for supported machine-bound hosts; dongle hosting requires the physical
   WIBU USB dongle.
2. Install CodeMeter Lite on `vps1`.
3. Confirm outbound cloud access with `cmu --verify-cloud-connection`.
4. Securely copy the vendor-issued `.wbc` to `vps1`.
5. Import it:

   ```bash
   cmu --import --file /home/oliver/140-560129638.wbc
   ```

6. Verify the new container with `cmu --list` and `cmu --list-content`.
7. Give the activation browser temporary access to `vps1` CodeMeter protocol
   and WebAdmin ports through SSH:

   ```bash
   ssh -N \
     -L 22350:127.0.0.1:22350 \
     -L 22352:127.0.0.1:22352 \
     vps1
   ```

8. WebDepot then detects `140-560129638 (15527_18864)`; activate all assigned
   items against it.
9. Confirm all items show **Activated**, verify content again on `vps1`, then
   remove the temporary `.wbc` from `vps1`.
10. Keep the original credentials archive in the encrypted vault.

WebDepot initially displayed **No key found** because the CmCloud credential
had not yet been imported. The license file-selection field expects a
CodeMeter request file (`.WibuCmRaC`), not the credential archive or an ARDIS
license-definition file.

Do not record the WebDepot ticket/activation URL in this repository. Do not
click **Re-Host Licenses** or **Change hosting type** unless deliberately
migrating/recovering the license with ARDIS/WIBU guidance.

## Rebuilding `vps1`

1. Recreate a supported, continuously connected Linux VM with correct time
   synchronization.
2. Install the current supported CodeMeter Lite package from WIBU/ARDIS.
3. Restore the secured `.wbc` credential archive from the encrypted vault.
4. Import the `.wbc` once.
5. Verify the cloud connection, container serial, Firm Code, and product
   inventory with the commands above.
6. Set `BindAddress=127.0.0.1` and `IsNetworkServer=1`, then confirm port
   `22350` remains loopback-only.
7. Restore SSH access through the `vps1` alias.
8. Validate a workstation tunnel before testing an application.

The activated entitlements are held in CmCloud. A normal server rebuild should
start by restoring the credential, not by re-hosting the licenses in WebDepot.
If restoration fails or WebDepot reports a container conflict, stop and
contact ARDIS/WIBU before performing a re-host.

## Security and availability rules

- `vps1` is the single license authority and therefore an availability
  dependency for all clients.
- Do not expose TCP `22350` or `22352` publicly.
- Do not bind the workstation tunnel to `0.0.0.0`.
- Do not distribute or commit the `.wbc` credential/archive.
- Client machines receive network access to the license server, never the
  credential itself.
- The tunnel requires key-based SSH and uses keepalives plus
  `ExitOnForwardFailure`.
- Loss of `vps1`, SSH, CmCloud Internet access, or correct server time can
  prevent new license acquisition.
- APO and PERFORM currently have a 120-second linger; do not assume indefinite
  offline operation from that setting.

## Troubleshooting order

1. Run `v1-license-tunnel-status`.
2. Test TCP from the actual client:
   - macOS/Linux: `127.0.0.1:22350`
   - Windows CERBER: `10.211.55.2:22350`
   - Docker: `host.docker.internal:22350`
3. Check `codemeter.service` and the loopback listener on `vps1`.
4. Run `cmu --verify-cloud-connection` and `cmu --list` on `vps1`.
5. Confirm the client's CodeMeter Server Search List points at the correct
   workstation address.
6. Confirm the application requests the expected WID and Product Code.
7. Check available seat quantity and restart/refresh the application.

Interpret common failures as follows:

| Symptom | Likely layer |
| --- | --- |
| “Please install WIBU CodeMeter drivers” | Client CodeMeter Runtime is missing |
| TCP test fails | Tunnel, SSH, bind address, or workstation networking |
| No CmContainer on `vps1` | Credential, service, or CmCloud connection |
| Container is visible but app rejects it | WID/Product Code, definition file, seat availability, or vendor configuration |
| Localhost works but Windows fails | Parallels bridge listener or Windows route/firewall |
| OPTIMIZER shows `(LOCAL)` / Error 200 | Active profile has `KeyLocal=1`; change that configuration to `KeyLocal=0` |
| One Demo Tools configuration works but another fails | Each configuration has its own `OPTIMIZER.ini`; verify `KeyLocal=0` in the newly selected profile |

For server diagnostics, inspect recent logs without changing state:

```bash
journalctl -u codemeter --since "30 minutes ago"
```
