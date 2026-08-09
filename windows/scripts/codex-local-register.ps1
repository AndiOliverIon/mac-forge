[CmdletBinding()]
param(
  [switch]$Verify
)

$ErrorActionPreference = "Stop"

function Get-BundleValue {
  param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$Name
  )

  $line = Get-Content -LiteralPath $ManifestPath | Where-Object {
    $_ -match "^$([regex]::Escape($Name))="
  } | Select-Object -First 1
  if (-not $line) {
    throw "Bundle manifest is missing $Name."
  }
  return $line.Substring($Name.Length + 1).Trim()
}

function Assert-BundleValue {
  param([string]$Name, [string]$Value, [string]$Pattern)
  if ($Value -notmatch $Pattern) {
    throw "Bundle value $Name is invalid."
  }
}

function Set-OwnerOnlyFile {
  param([Parameter(Mandatory)][string]$Path)

  try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      $identity,
      [System.Security.AccessControl.FileSystemRights]::FullControl,
      [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
  } catch {
    Write-Warning "Could not restrict $Path to the current user: $($_.Exception.Message)"
  }
}

$bundlePath = (Get-Location).Path
$manifestPath = Join-Path $bundlePath "manifest.env"
$certificatePath = Join-Path $bundlePath "local-llm-root.crt"
$keyPath = Join-Path $bundlePath "local-llm.key"

foreach ($requiredPath in @($manifestPath, $certificatePath, $keyPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "This command must run from a local LLM deployment bundle. Missing: $requiredPath"
  }
}

$bundleFormat = Get-BundleValue $manifestPath "BUNDLE_FORMAT"
$profileName = Get-BundleValue $manifestPath "PROFILE_NAME"
$providerId = Get-BundleValue $manifestPath "PROVIDER_ID"
$displayName = Get-BundleValue $manifestPath "DISPLAY_NAME"
$baseUrl = Get-BundleValue $manifestPath "BASE_URL"
$defaultModel = Get-BundleValue $manifestPath "DEFAULT_MODEL"

if ($bundleFormat -ne "1") { throw "Unsupported local LLM bundle format: $bundleFormat" }
Assert-BundleValue "PROFILE_NAME" $profileName "^[A-Za-z0-9_-]+$"
Assert-BundleValue "PROVIDER_ID" $providerId "^[A-Za-z0-9_-]+$"
Assert-BundleValue "BASE_URL" $baseUrl "^https://[A-Za-z0-9.-]+(?::[0-9]+)?/v1$"
Assert-BundleValue "DEFAULT_MODEL" $defaultModel "^[A-Za-z0-9._:-]+$"

$apiKey = (Get-Content -LiteralPath $keyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match "\s") {
  throw "local-llm.key must contain one non-empty API key with no whitespace."
}

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
New-Item -ItemType Directory -Path $codexHome -Force | Out-Null

$tokenPath = Join-Path $codexHome "$profileName.token"
$tokenHelperPath = Join-Path $codexHome "$profileName-token.ps1"
$profilePath = Join-Path $codexHome "$profileName.config.toml"

[System.IO.File]::WriteAllText($tokenPath, "$apiKey`n", [System.Text.UTF8Encoding]::new($false))
Set-OwnerOnlyFile $tokenPath

$tokenHelper = @'
$ErrorActionPreference = "Stop"
$tokenPath = Join-Path $PSScriptRoot "local-lan.token"
$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "The local LAN token file is empty."
}
[Console]::Write($token)
'@
$tokenHelper = $tokenHelper.Replace("local-lan.token", "$profileName.token")
[System.IO.File]::WriteAllText($tokenHelperPath, $tokenHelper, [System.Text.UTF8Encoding]::new($false))
Set-OwnerOnlyFile $tokenHelperPath

try {
  Import-Certificate -FilePath $certificatePath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
} catch {
  throw "Could not trust the local LLM certificate for this user: $($_.Exception.Message)"
}

if (Test-Path -LiteralPath $profilePath) {
  $backupPath = "$profilePath.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item -LiteralPath $profilePath -Destination $backupPath
  Write-Host "Backed up the existing profile to $backupPath"
}

$tomlTokenHelperPath = $tokenHelperPath.Replace("\", "/")
$profile = @"
model = "$defaultModel"
model_provider = "$providerId"

[model_providers.$providerId]
name = "$displayName"
base_url = "$baseUrl"
wire_api = "responses"
request_max_retries = 1
stream_idle_timeout_ms = 120000

[model_providers.$providerId.auth]
command = "powershell.exe"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$tomlTokenHelperPath"]
timeout_ms = 5000
refresh_interval_ms = 0
"@
[System.IO.File]::WriteAllText($profilePath, $profile, [System.Text.UTF8Encoding]::new($false))
Set-OwnerOnlyFile $profilePath

Write-Host "Registered Codex profile '$profileName' for $displayName."
Write-Host "Use it with: codex --profile $profileName"

$codexCommand = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codexCommand) {
  Write-Warning "Codex CLI is not installed or not on PATH. Install it, open a new terminal, then run: codex --profile $profileName"
  exit 0
}

if ($Verify) {
  & codex --profile $profileName exec --skip-git-repo-check "Reply exactly: local LAN registration verified."
}
