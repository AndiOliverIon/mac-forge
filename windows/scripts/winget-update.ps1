[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$forgeRoot = Split-Path -Parent $windowsRoot

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $forgeRoot "config-local\winget.json"
}

function Split-ForgeWingetArguments([string]$Line) {
  $matches = [regex]::Matches($Line, '("[^"]*"|''[^'']*''|\S+)')
  foreach ($match in $matches) {
    $value = $match.Value
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $value
  }
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
  throw "winget is required. Install or repair Microsoft App Installer, then rerun winget-update."
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw "Winget update config not found: $ConfigPath"
}

$lines = Get-Content -LiteralPath $ConfigPath
$commands = @(
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    $trimmed
  }
)

if ($commands.Count -eq 0) {
  Write-Host "No winget update entries found in $ConfigPath."
  return
}

$failures = @()
foreach ($command in $commands) {
  $arguments = @("update") + @(Split-ForgeWingetArguments $command)
  Write-Host ""
  Write-Host "winget $($arguments -join ' ')" -ForegroundColor Cyan
  if ($PSCmdlet.ShouldProcess($command, "winget update")) {
    & winget @arguments
    if ($LASTEXITCODE -ne 0) {
      $failures += $command
      Write-Warning "winget update failed for '$command' (exit code $LASTEXITCODE)."
    }
  }
}

if ($failures.Count -gt 0) {
  throw "Winget update failed for: $($failures -join ', ')"
}
