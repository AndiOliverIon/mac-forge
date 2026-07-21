[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$themeFile = Join-Path $windowsRoot "config\terminal-theme.json"
$theme = Get-Content -LiteralPath $themeFile -Raw | ConvertFrom-Json

$candidates = @(
  (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
  (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
  (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
)
$settingsPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $settingsPath) {
  throw "Windows Terminal settings were not found. Launch Windows Terminal once, then rerun this script."
}

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if (-not $settings.profiles) {
  $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{})
}
if (-not $settings.profiles.defaults) {
  $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
}
$defaults = $settings.profiles.defaults

foreach ($property in @{
  colorScheme = "Forge"
  opacity = 88
  useAcrylic = $true
  padding = "12"
}.GetEnumerator()) {
  if ($defaults.PSObject.Properties[$property.Key]) {
    $defaults.$($property.Key) = $property.Value
  } else {
    $defaults | Add-Member -NotePropertyName $property.Key -NotePropertyValue $property.Value
  }
}

if (-not $defaults.font) {
  $defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
}
if ($defaults.font.PSObject.Properties["face"]) {
  $defaults.font.face = "JetBrainsMono Nerd Font"
} else {
  $defaults.font | Add-Member -NotePropertyName face -NotePropertyValue "JetBrainsMono Nerd Font"
}

$schemes = @($settings.schemes | Where-Object { $_.name -ne "Forge" })
$schemes += $theme
if ($settings.PSObject.Properties["schemes"]) {
  $settings.schemes = $schemes
} else {
  $settings | Add-Member -NotePropertyName schemes -NotePropertyValue $schemes
}

$powerShell7Profile = @($settings.profiles.list | Where-Object {
  $_.source -eq "Windows.Terminal.PowershellCore" -and -not $_.hidden
}) | Select-Object -First 1
if ($powerShell7Profile) {
  if ($settings.PSObject.Properties["defaultProfile"]) {
    $settings.defaultProfile = $powerShell7Profile.guid
  } else {
    $settings | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $powerShell7Profile.guid
  }
}

if ($PSCmdlet.ShouldProcess($settingsPath, "Back up and apply Forge terminal defaults")) {
  $backupPath = "$settingsPath.bak.$(Get-Date -Format yyyyMMddHHmmss)"
  Copy-Item -LiteralPath $settingsPath -Destination $backupPath
  $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
  Write-Host "Configured Windows Terminal: $settingsPath"
  Write-Host "Backup: $backupPath"
}
