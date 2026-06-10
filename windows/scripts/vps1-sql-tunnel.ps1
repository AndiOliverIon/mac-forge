param(
  [ValidateSet("up", "down", "status", "help")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$SshHost = if ($env:VPS1_SSH_HOST) { $env:VPS1_SSH_HOST } else { "vps1" }
$LocalPort = if ($env:SQL_LOCAL_PORT) { [int]$env:SQL_LOCAL_PORT } else { 14333 }
$Remote = if ($env:SQL_REMOTE) { $env:SQL_REMOTE } else { "127.0.0.1:1433" }
$ForwardSpec = "127.0.0.1:$($LocalPort):$Remote"

function Write-Step {
  param([string]$Message)
  Write-Host "-> $Message"
}

function Stop-WithError {
  param([string]$Message)
  Write-Error $Message
  exit 1
}

function Get-Listener {
  Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
}

function Get-TunnelProcess {
  $needle = "-L $ForwardSpec"
  Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      $cmd -and (
        $cmd.Contains($needle) -or
        $cmd.Contains("-L$ForwardSpec")
      )
    }
}

function Test-TunnelUp {
  [bool](Get-Listener)
}

function Open-Tunnel {
  if (Test-TunnelUp) {
    Write-Step "SQL tunnel already up - localhost:$LocalPort -> ${SshHost}:$Remote"
  } else {
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) {
      Stop-WithError "Required command 'ssh' not found. Install or enable OpenSSH Client on Windows."
    }

    Write-Step "Opening SQL tunnel localhost:$LocalPort -> ${SshHost}:$Remote ..."
    $args = @(
      "-N",
      "-L", $ForwardSpec,
      "-o", "ExitOnForwardFailure=yes",
      "-o", "ServerAliveInterval=30",
      "-o", "BatchMode=yes",
      $SshHost
    )

    Start-Process -FilePath $ssh.Source -ArgumentList $args -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 1
  }

  if (Test-TunnelUp) {
    Write-Host "OK SQL reachable at localhost:$LocalPort (VS Code: Server = localhost,$LocalPort)"
    $pids = @(Get-TunnelProcess | Select-Object -ExpandProperty ProcessId)
    if ($pids.Count -gt 0) {
      Write-Host "  (ssh pid: $($pids -join ' ')) - close with: v1-sql-tunnel-down"
    }
  } else {
    Stop-WithError "Tunnel did not come up on localhost:$LocalPort."
  }
}

function Close-Tunnel {
  $processes = @(Get-TunnelProcess)
  if ($processes.Count -eq 0) {
    Write-Step "No vps1 SQL tunnel found (nothing to close)."
    return
  }

  $pids = @($processes | Select-Object -ExpandProperty ProcessId)
  Write-Step "Closing SQL tunnel (ssh pid: $($pids -join ' ')) ..."
  $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Start-Sleep -Seconds 1

  if (Test-TunnelUp) {
    Stop-WithError "Port $LocalPort still in use after closing. Check: Get-NetTCPConnection -LocalPort $LocalPort"
  }

  Write-Host "OK SQL tunnel closed."
}

function Show-Status {
  if (Test-TunnelUp) {
    $pids = @(Get-TunnelProcess | Select-Object -ExpandProperty ProcessId)
    $pidText = if ($pids.Count -gt 0) { "  (ssh pid: $($pids -join ' '))" } else { "" }
    Write-Host "UP - localhost:$LocalPort -> ${SshHost}:$Remote$pidText"
  } else {
    Write-Host "DOWN - no listener on localhost:$LocalPort. Open with: v1-sql-tunnel-up"
  }
}

function Show-Help {
  Write-Host @"
vps1-sql-tunnel.ps1 - open/close the SSH tunnel to the private vps1 SQL Server.

The MSSQL container binds to 127.0.0.1:1433 on vps1 and is not public.
Each Windows station should open its own local tunnel and connect tools to:

  Server = localhost,$LocalPort

Usage:
  vps1-sql-tunnel.ps1 up
  vps1-sql-tunnel.ps1 down
  vps1-sql-tunnel.ps1 status

Environment overrides:
  VPS1_SSH_HOST   default: vps1
  SQL_LOCAL_PORT  default: 14333
  SQL_REMOTE      default: 127.0.0.1:1433
"@
}

switch ($Action) {
  "up" { Open-Tunnel }
  "down" { Close-Tunnel }
  "status" { Show-Status }
  "help" { Show-Help }
}
