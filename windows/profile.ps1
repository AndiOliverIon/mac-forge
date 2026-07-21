# mac-forge PowerShell profile entry point.

$script:ForgeWindowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ForgeRoot = Split-Path -Parent $script:ForgeWindowsRoot

. (Join-Path $script:ForgeWindowsRoot "aliases.ps1")

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  $theme = Join-Path $script:ForgeRoot "profiles\minimal.json"
  oh-my-posh init pwsh --config $theme | Invoke-Expression
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
