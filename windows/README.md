# Windows scripts

Windows helpers for stations that use the shared `mac-forge` toolbox.

## Aliases

Load the Windows aliases in the current PowerShell session:

```powershell
. .\windows\aliases.ps1
```

Then the tunnel commands are available as:

```powershell
v1-sql-tunnel-up
v1-sql-tunnel-down
v1-sql-tunnel-status
```

## VPS1 SQL tunnel

Run this on each Windows station that needs direct SQL tooling access to VPS1:

```powershell
v1-sql-tunnel-up
```

Then connect SQL clients to:

```text
localhost,14333
```

Close the tunnel with:

```powershell
v1-sql-tunnel-down
```

The tunnel uses the local Windows OpenSSH client and expects the SSH alias `vps1`
to exist in that station's SSH config. SQL remains private on VPS1; each station
gets its own local `localhost:14333` relay.

Before using the tunnel wrappers, confirm this works from the Windows station:

```cmd
ssh vps1
```

The tunnel starts SSH in non-interactive mode, so key-based authentication should
already be configured.
