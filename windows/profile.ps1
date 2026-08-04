# mac-forge PowerShell profile entry point.

if ($global:ForgeWindowsProfileLoaded) { return }
$global:ForgeWindowsProfileLoaded = $true

$script:ForgeWindowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ForgeRoot = Split-Path -Parent $script:ForgeWindowsRoot

. (Join-Path $script:ForgeWindowsRoot "aliases.ps1")

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  $theme = Join-Path $script:ForgeRoot "profiles\minimal.json"
  try {
    $poshInit = & oh-my-posh init pwsh --config $theme 2>$null
    if ($LASTEXITCODE -eq 0 -and $poshInit) {
      $poshInit | Invoke-Expression
    }
  } catch {
    # Prompt setup is cosmetic; Forge commands should still load.
  }
}

if (Get-Module -ListAvailable -Name PSReadLine) {
  Import-Module PSReadLine
  Set-PSReadLineOption -EditMode Windows
  Set-PSReadLineOption -HistoryNoDuplicates
  if (
    -not [Console]::IsOutputRedirected -and
    (Get-Command Set-PSReadLineOption).Parameters.ContainsKey("PredictionSource")
  ) {
    Set-PSReadLineOption -PredictionSource History
  }
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
}
