[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$SkipPackages,
  [switch]$SkipTerminal
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$forgeRoot = Split-Path -Parent $windowsRoot
$script:PackageFailures = @()

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Install-WingetPackage([string]$Id) {
  $installed = winget list --id $Id --exact --accept-source-agreements 2>$null
  if ($LASTEXITCODE -eq 0 -and $installed -match [regex]::Escape($Id)) {
    Write-Host "Already installed: $Id"
    return
  }
  if ($PSCmdlet.ShouldProcess($Id, "Install with winget")) {
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
      $verification = winget list --id $Id --exact --accept-source-agreements 2>$null
      if ($LASTEXITCODE -eq 0 -and $verification -match [regex]::Escape($Id)) {
        Write-Warning "winget returned $installExitCode for $Id, but the package is installed."
      } else {
        Write-Warning "winget failed to install $Id (exit code $installExitCode)."
        $script:PackageFailures += $Id
      }
    }
  }
}

Write-Step "Checking prerequisites"
if (-not $SkipPackages) {
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw "winget is required. Install or repair Microsoft App Installer, then rerun bootstrap."
  }

  $packages = @(
    "Microsoft.WindowsTerminal",
    "Microsoft.PowerShell",
    "Git.Git",
    "JanDeDobbeleer.OhMyPosh",
    "DEVCOM.JetBrainsMonoNerdFont",
    "BurntSushi.ripgrep.MSVC",
    "junegunn.fzf",
    "jqlang.jq",
    "Python.Python.3.13",
    "OpenJS.NodeJS.LTS",
    "GitHub.cli",
    "Microsoft.Sqlcmd",
    "Microsoft.VisualStudioCode",
    "JetBrains.Rider",
    "Docker.DockerDesktop",
    "Microsoft.DotNet.SDK.8",
    "Microsoft.DotNet.SDK.9",
    "Microsoft.DotNet.SDK.10"
  )

  Write-Step "Installing workstation packages"
  foreach ($package in $packages) {
    Install-WingetPackage $package
  }
}

Write-Step "Allowing locally authored profile scripts for the current user"
if ($PSCmdlet.ShouldProcess("CurrentUser", "Set PowerShell execution policy to RemoteSigned")) {
  try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
  } catch {
    $persistedPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($persistedPolicy -ne "RemoteSigned") {
      throw
    }
    Write-Warning "RemoteSigned was persisted for CurrentUser; this bootstrap process remains under its temporary Bypass policy."
  }
}

Write-Step "Configuring the Windows PowerShell and PowerShell 7 profiles"
$loader = ". `"$windowsRoot\profile.ps1`""
$profilePaths = @(
  (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\profile.ps1"),
  (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\profile.ps1")
)
foreach ($profilePath in $profilePaths) {
  $profileDirectory = Split-Path -Parent $profilePath
  if ($PSCmdlet.ShouldProcess($profilePath, "Add mac-forge profile loader")) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $profilePath)) {
      New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }
    $profileContent = Get-Content -LiteralPath $profilePath -Raw
    if ($null -eq $profileContent) { $profileContent = "" }
    if (-not $profileContent.Contains($loader)) {
      if ($profileContent.Length -gt 0 -and -not $profileContent.EndsWith([Environment]::NewLine)) {
        Add-Content -LiteralPath $profilePath -Value ""
      }
      Add-Content -LiteralPath $profilePath -Value $loader
    }
    Write-Host "PowerShell profile: $profilePath"
  }
}

if (-not $SkipTerminal) {
  Write-Step "Configuring Windows Terminal"
  $terminalScript = Join-Path $windowsRoot "scripts\configure-terminal.ps1"
  try {
    & $terminalScript -WhatIf:$WhatIfPreference
  } catch {
    Write-Warning $_.Exception.Message
  }
}

Write-Step "Validating Forge command loading"
if ($WhatIfPreference) {
  Write-Host "Skipped command loading validation during -WhatIf."
} else {
  . (Join-Path $windowsRoot "profile.ps1")
  foreach ($command in @("forge", "switch", "dnc", "v1sn", "v1-sql-tunnel-status")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
      throw "Expected Forge command was not loaded: $command"
    }
  }
}

Write-Host ""
Write-Host "Windows Forge bootstrap complete." -ForegroundColor Green
Write-Host "Open a new PowerShell 7 terminal, then run: forge"
Write-Host "Private Forge values belong under: $forgeRoot\config-local"
if ($script:PackageFailures.Count -gt 0) {
  Write-Warning "Packages requiring manual attention: $($script:PackageFailures -join ', ')"
}
