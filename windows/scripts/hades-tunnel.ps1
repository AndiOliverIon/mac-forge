param(
  [Parameter(Mandatory)]
  [ValidateSet("up", "down", "status")]
  [string]$Action
)

$ErrorActionPreference = "Stop"

$forwards = @(
  @{ LocalPort = 4200; Remote = "localhost:4200"; Label = "Angular" }
  @{ LocalPort = 8080; Remote = "localhost:8080"; Label = "Perform API" }
)
$sshHost = if ($env:HADES_SSH_HOST) { $env:HADES_SSH_HOST } else { "hades" }
$sshIdentity = if ($env:HADES_SSH_IDENTITY_FILE) {
  $env:HADES_SSH_IDENTITY_FILE
} else {
  Join-Path $HOME ".ssh\id_ed25519_hades_tunnel"
}
$forwardSpecs = @($forwards | ForEach-Object { "127.0.0.1:$($_.LocalPort):$($_.Remote)" })

function Get-TunnelProcess {
  @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $commandLine = $_.CommandLine
      if (-not $commandLine) { return $false }

      foreach ($forwardSpec in $forwardSpecs) {
        if (-not ($commandLine.Contains("-L $forwardSpec") -or $commandLine.Contains("-L$forwardSpec"))) {
          return $false
        }
      }
      return $true
    })
}

function Get-PortListeners {
  @($forwards | ForEach-Object {
    Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $_.LocalPort -State Listen -ErrorAction SilentlyContinue
  })
}

function Wait-ForState([bool]$Expected) {
  foreach ($attempt in 1..20) {
    $listenerCount = (Get-PortListeners).Count
    if (($Expected -and $listenerCount -eq $forwards.Count) -or (-not $Expected -and $listenerCount -eq 0)) {
      return $true
    }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

function Open-Tunnel {
  $processes = @(Get-TunnelProcess)
  $listeners = @(Get-PortListeners)
  $processIds = @($processes | Select-Object -ExpandProperty ProcessId)
  $conflicts = @($listeners | Where-Object { $_.OwningProcess -notin $processIds })
  if ($conflicts.Count -gt 0) {
    $ports = @($conflicts | Select-Object -ExpandProperty LocalPort -Unique)
    throw "Port(s) $($ports -join ', ') are already used by a process that is not this Forge tunnel."
  }
  if ($processes.Count -gt 0 -and $listeners.Count -eq $forwards.Count) {
    Write-Host "UP - Hades tunnel already provides localhost:4200 and localhost:8080."
    return
  }
  if ($processes.Count -gt 0) {
    $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    if (-not (Wait-ForState $false)) {
      throw "A stale Hades tunnel process could not be cleared."
    }
  }

  $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
  if (-not $ssh) { throw "Windows OpenSSH Client is required." }
  if (-not (Test-Path -LiteralPath $sshIdentity -PathType Leaf)) {
    throw "Hades tunnel SSH identity not found: $sshIdentity"
  }

  $arguments = @("-N", "-i", $sshIdentity)
  foreach ($forwardSpec in $forwardSpecs) {
    $arguments += @("-L", $forwardSpec)
  }
  $arguments += @(
    "-o", "ExitOnForwardFailure=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "BatchMode=yes",
    $sshHost
  )

  $process = Start-Process -FilePath $ssh.Source -ArgumentList $arguments -WindowStyle Hidden -PassThru
  if (-not (Wait-ForState $true)) {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    throw "The Hades tunnel did not open. Verify: ssh -i $sshIdentity $sshHost"
  }
  Write-Host "OK - Hades Angular and Perform API tunnels are available at localhost:4200 and localhost:8080 (ssh pid: $($process.Id))."
}

function Close-Tunnel {
  $processes = @(Get-TunnelProcess)
  if ($processes.Count -eq 0) {
    Write-Host "DOWN - no Hades Forge tunnel found."
    return
  }

  $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  if (-not (Wait-ForState $false)) {
    throw "A Hades tunnel port is still listening after the tunnel process stopped."
  }
  Write-Host "OK - Hades Angular and Perform API tunnels closed."
}

function Show-TunnelStatus {
  $processes = @(Get-TunnelProcess)
  $listeners = @(Get-PortListeners)
  $processIds = @($processes | Select-Object -ExpandProperty ProcessId)
  $tunnelListeners = @($listeners | Where-Object { $_.OwningProcess -in $processIds })
  $conflicts = @($listeners | Where-Object { $_.OwningProcess -notin $processIds })

  if ($conflicts.Count -gt 0) {
    $ports = @($conflicts | Select-Object -ExpandProperty LocalPort -Unique)
    Write-Host "CONFLICT - port(s) $($ports -join ', ') are used by a process that is not this Forge tunnel."
    return
  }

  $tunnelPorts = @($tunnelListeners | Select-Object -ExpandProperty LocalPort -Unique)
  if ($processes.Count -gt 0 -and $tunnelPorts.Count -eq $forwards.Count) {
    Write-Host "UP - localhost:4200 and localhost:8080 -> $sshHost (ssh pid: $($processIds -join ', '))."
  } elseif ($processes.Count -gt 0 -or $tunnelPorts.Count -gt 0) {
    Write-Host "PARTIAL - the Hades tunnel is not listening on every configured port. Reopen with: hades-tunnel-up"
  } else {
    Write-Host "DOWN - no Hades Forge tunnel found. Open with: hades-tunnel-up"
  }
}

switch ($Action) {
  "up" { Open-Tunnel }
  "down" { Close-Tunnel }
  "status" { Show-TunnelStatus }
}
