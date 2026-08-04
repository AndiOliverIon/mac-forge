[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$SkipPackages,
  [switch]$SkipTerminal,
  [switch]$SkipGlobalTools,
  [switch]$SkipLicense
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$forgeRoot = Split-Path -Parent $windowsRoot
$angularCliVersion = "20.3.16"
$yarnVersion = "1.22.22"
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

function Add-ForgeUserPathEntry([string]$Path) {
  if (-not $Path) { return }
  $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $entries = @($userPath -split ";" | Where-Object { $_ })
  if ($entries -notcontains $expandedPath) {
    if ($PSCmdlet.ShouldProcess($expandedPath, "Add to current-user PATH")) {
      $entries += $expandedPath
      [Environment]::SetEnvironmentVariable("Path", ($entries -join ";"), "User")
    }
  }
  if (($env:Path -split ";") -notcontains $expandedPath) {
    $env:Path = "$env:Path;$expandedPath"
  }
}

function Sync-ForgeSessionPath {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $processPath = [Environment]::GetEnvironmentVariable("Path", "Process")
  $env:Path = @($processPath, $machinePath, $userPath) -join ";"
}

function Invoke-ForgeInstaller([string]$Command, [string[]]$Arguments, [string]$Target) {
  if ($PSCmdlet.ShouldProcess($Target, "$Command $($Arguments -join ' ')")) {
    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      Write-Warning "$Command failed for $Target (exit code $exitCode)."
      $script:PackageFailures += $Target
    }
  }
}

function Install-NpmGlobalPackage([string]$Spec, [string]$Name, [string]$RequiredVersion = "") {
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npm) {
    Write-Warning "npm was not found; skipping $Spec."
    $script:PackageFailures += $Spec
    return
  }

  $installedVersion = ""
  $listOutput = & $npm.Source list --global --depth=0 --json $Name 2>$null
  if ($LASTEXITCODE -eq 0 -and $listOutput) {
    try {
      $packageInfo = ($listOutput | Out-String | ConvertFrom-Json)
      $dependency = $packageInfo.dependencies.PSObject.Properties[$Name]
      if ($dependency) {
        $installedVersion = $dependency.Value.version
      }
    } catch {
      $installedVersion = ""
    }
  }

  if ($installedVersion -and (-not $RequiredVersion -or $installedVersion -eq $RequiredVersion)) {
    Write-Host "Already installed: $Name $installedVersion"
    return
  }

  Invoke-ForgeInstaller $npm.Source @("install", "--global", $Spec) $Spec
}

function Install-ForgeGlobalTools {
  Sync-ForgeSessionPath
  Add-ForgeUserPathEntry (Join-Path $HOME ".local\bin")
  Add-ForgeUserPathEntry (Join-Path $env:APPDATA "npm")
  Sync-ForgeSessionPath

  Install-NpmGlobalPackage "@openai/codex" "@openai/codex"
  Install-NpmGlobalPackage "@angular/cli@$angularCliVersion" "@angular/cli" $angularCliVersion
  Install-NpmGlobalPackage "vsts-npm-auth" "vsts-npm-auth"

  $corepack = Get-Command corepack.cmd -ErrorAction SilentlyContinue
  if ($corepack) {
    Invoke-ForgeInstaller $corepack.Source @("enable") "corepack"
    Invoke-ForgeInstaller $corepack.Source @("install", "--global", "yarn@$yarnVersion") "yarn@$yarnVersion"
  } else {
    Write-Warning "corepack was not found; skipping Yarn $yarnVersion."
    $script:PackageFailures += "yarn@$yarnVersion"
  }
}

function Install-TelerikLicense {
  $destinationDirectory = Join-Path $HOME ".telerik"
  $destinationFile = Join-Path $destinationDirectory "telerik-license.txt"
  $candidates = @()
  if ($env:TELERIK_LICENSE_SOURCE_DIR) {
    $candidates += $env:TELERIK_LICENSE_SOURCE_DIR
  }
  $candidates += @(
    (Join-Path (Get-Location) ".telerik"),
    (Join-Path $forgeRoot ".telerik"),
    (Join-Path $forgeRoot "config-local\.telerik"),
    $destinationDirectory
  )

  $sourceFile = $null
  foreach ($candidate in $candidates) {
    $candidateFile = Join-Path $candidate "telerik-license.txt"
    if (Test-Path -LiteralPath $candidateFile -PathType Leaf) {
      $sourceFile = $candidateFile
      break
    }
  }

  if (-not $sourceFile) {
    Write-Warning "Telerik license was not found. Stage .telerik\telerik-license.txt or set TELERIK_LICENSE_SOURCE_DIR, then rerun bootstrap."
    return
  }

  if ($sourceFile -eq $destinationFile) {
    Write-Host "Telerik license already installed at $destinationFile."
    return
  }

  if ($PSCmdlet.ShouldProcess($destinationFile, "Install staged Telerik license")) {
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force
    Write-Host "Telerik license installed at $destinationFile."
    Write-Host "The source copy was left in place; remove it after verifying the workstation."
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
    "GitHub.Copilot",
    "Anthropic.ClaudeCode",
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

if (-not $SkipGlobalTools) {
  Write-Step "Installing global developer CLIs"
  Install-ForgeGlobalTools
}

if (-not $SkipLicense) {
  Write-Step "Configuring commercial UI license files"
  Install-TelerikLicense
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
  (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
  (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\profile.ps1"),
  (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1")
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
