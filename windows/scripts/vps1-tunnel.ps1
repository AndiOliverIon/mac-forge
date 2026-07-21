param(
  [Parameter(Mandatory)]
  [ValidateSet("sql", "license", "bl", "meerkat", "tally")]
  [string]$Name,
  [Parameter(Mandatory)]
  [ValidateSet("up", "down", "status")]
  [string]$Action
)

$ErrorActionPreference = "Stop"

$definitions = @{
  sql = @{ LocalPort = 14333; Remote = "127.0.0.1:1433"; Label = "SQL" }
  license = @{ LocalPort = 22350; Remote = "127.0.0.1:22350"; Label = "CodeMeter" }
  bl = @{ LocalPort = 5081; Remote = "127.0.0.1:5081"; Label = "BookingLounge dev API" }
  meerkat = @{ LocalPort = 5281; Remote = "127.0.0.1:5281"; Label = "Meerkat dev API" }
  tally = @{ LocalPort = 5181; Remote = "127.0.0.1:5181"; Label = "Tally dev API" }
}

$definition = $definitions[$Name]
$sshHost = if ($env:VPS1_SSH_HOST) { $env:VPS1_SSH_HOST } else { "vps1" }
$localPort = [int]$definition.LocalPort
$remote = [string]$definition.Remote
$forwardSpec = "127.0.0.1:$localPort`:$remote"

function Get-TunnelProcess {
  $needles = @("-L $forwardSpec", "-L$forwardSpec")
  @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $commandLine = $_.CommandLine
      $commandLine -and ($needles | Where-Object { $commandLine.Contains($_) })
    })
}

function Get-PortListener {
  @(Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue)
}

function Wait-ForState([bool]$Expected) {
  foreach ($attempt in 1..20) {
    if ([bool](Get-PortListener) -eq $Expected) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

function Open-Tunnel {
  $processes = @(Get-TunnelProcess)
  $listeners = @(Get-PortListener)
  if ($listeners.Count -gt 0 -and $processes.Count -eq 0) {
    throw "Port $localPort is already used by a process that is not this Forge tunnel."
  }
  if ($processes.Count -gt 0 -and $listeners.Count -gt 0) {
    Write-Host "UP - $($definition.Label) tunnel already available at localhost:$localPort"
    return
  }

  $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
  if (-not $ssh) { throw "Windows OpenSSH Client is required." }

  $arguments = @(
    "-N", "-L", $forwardSpec,
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "BatchMode=yes",
    $sshHost
  )
  $process = Start-Process -FilePath $ssh.Source -ArgumentList $arguments -WindowStyle Hidden -PassThru
  if (-not (Wait-ForState $true)) {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    throw "The $($definition.Label) tunnel did not open on localhost:$localPort. Verify: ssh $sshHost"
  }
  Write-Host "OK - $($definition.Label) available at localhost:$localPort (ssh pid: $($process.Id))"
}

function Close-Tunnel {
  $processes = @(Get-TunnelProcess)
  if ($processes.Count -eq 0) {
    Write-Host "DOWN - no $($definition.Label) Forge tunnel found."
    return
  }
  $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  if (-not (Wait-ForState $false)) {
    throw "Port $localPort is still listening after the tunnel process stopped."
  }
  Write-Host "OK - $($definition.Label) tunnel closed."
}

function Show-Status {
  $processes = @(Get-TunnelProcess)
  $listeners = @(Get-PortListener)
  if ($processes.Count -gt 0 -and $listeners.Count -gt 0) {
    $ids = @($processes | Select-Object -ExpandProperty ProcessId)
    Write-Host "UP - localhost:$localPort -> ${sshHost}:$remote (ssh pid: $($ids -join ', '))"
  } elseif ($listeners.Count -gt 0) {
    Write-Host "CONFLICT - localhost:$localPort is used by a non-Forge process."
  } elseif ($processes.Count -gt 0) {
    Write-Host "BROKEN - matching ssh process exists but localhost:$localPort is not listening."
  } else {
    Write-Host "DOWN - no $($definition.Label) tunnel."
  }
}

switch ($Action) {
  "up" { Open-Tunnel }
  "down" { Close-Tunnel }
  "status" { Show-Status }
}
