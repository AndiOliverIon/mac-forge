# Windows PowerShell command surface for the shared mac-forge workspace.

$script:ForgeWindowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ForgeRoot = Split-Path -Parent $script:ForgeWindowsRoot
$script:ForgeBash = @(
  (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
  (Join-Path $env:ProgramFiles "Git\usr\bin\bash.exe")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

function global:Invoke-ForgeBash {
  param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Script,
    [Parameter(ValueFromRemainingArguments)]
    [object[]]$Arguments
  )

  if (-not $script:ForgeBash) {
    throw "Git Bash was not found. Run windows\scripts\bootstrap.ps1 first."
  }

  $scriptPath = if ([System.IO.Path]::IsPathRooted($Script)) {
    $Script
  } else {
    Join-Path $script:ForgeRoot $Script
  }

  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Forge script not found: $scriptPath"
  }

  $previousMachine = $env:FORGE_MACHINE_NAME
  $previousRoot = $env:FORGE_ROOT
  $previousSecrets = $env:FORGE_SECRETS_FILE
  try {
    $env:FORGE_MACHINE_NAME = $env:COMPUTERNAME
    $env:FORGE_ROOT = (& $script:ForgeBash -c 'export PATH="/usr/bin:/mingw64/bin:$PATH"; cygpath -u "$1"' -- $script:ForgeRoot)

    $windowsSecrets = Join-Path $script:ForgeRoot "config-local\forge-secrets.sh"
    if (Test-Path -LiteralPath $windowsSecrets) {
      $env:FORGE_SECRETS_FILE = (& $script:ForgeBash -c 'export PATH="/usr/bin:/mingw64/bin:$PATH"; cygpath -u "$1"' -- $windowsSecrets)
    }

    $bashScriptPath = (& $script:ForgeBash -c 'export PATH="/usr/bin:/mingw64/bin:$PATH"; cygpath -u "$1"' -- $scriptPath)
    & $script:ForgeBash -c 'export PATH="/usr/bin:/mingw64/bin:$PATH"; script="$1"; shift; exec bash "$script" "$@"' -- $bashScriptPath @Arguments
  } finally {
    $env:FORGE_MACHINE_NAME = $previousMachine
    $env:FORGE_ROOT = $previousRoot
    $env:FORGE_SECRETS_FILE = $previousSecrets
  }
}

function Register-ForgeBashCommand {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Script,
    [string[]]$PrefixArguments = @()
  )

  $targetScript = $Script
  $targetPrefix = $PrefixArguments
  $implementation = {
    Invoke-ForgeBash $targetScript @targetPrefix @args
  }.GetNewClosure()
  Set-Item -Path "Function:\global:$Name" -Value $implementation -Force
}

function Register-ForgeAlias {
  param([string]$Name, [string]$Target)
  $existing = Get-Alias -Name $Name -ErrorAction SilentlyContinue
  $options = if ($existing -and ($existing.Options -band [System.Management.Automation.ScopedItemOptions]::AllScope)) {
    [System.Management.Automation.ScopedItemOptions]::AllScope
  } else {
    [System.Management.Automation.ScopedItemOptions]::None
  }
  Set-Alias -Name $Name -Value $Target -Scope Global -Option $options -Force
}

function Register-ForgeLocation {
  param([string]$Name, [string]$Path)
  $targetPath = $Path
  $implementation = { Set-Location -LiteralPath $targetPath }.GetNewClosure()
  Set-Item -Path "Function:\global:$Name" -Value $implementation -Force
}

function global:forge { Set-Location $script:ForgeRoot }
function global:oliver { Set-Location $HOME }
function global:doc { Set-Location (Join-Path $HOME "Documents") }
function global:desk { Set-Location (Join-Path $HOME "Desktop") }
function global:down { Set-Location (Join-Path $HOME "Downloads") }
function global:dev { Set-Location "C:\dev" }
function global:work { Set-Location "C:\work" }
function global:projects { Set-Location "C:\projects" }
function global:perf { Set-Location "C:\work\ardis-perform" }
function global:aliases { Get-Content (Join-Path $script:ForgeWindowsRoot "aliases.ps1") }
function global:reloadterm {
  . (Join-Path $script:ForgeWindowsRoot "aliases.ps1")
  Write-Host "Forge commands reloaded."
}
function global:help {
  $names = @(
    "forge", "perf", "info", "ftp", "switch", "dnc", "binclear", "genopenapi",
    "script-run", "sqlexec", "v1sn", "v1r", "v1list",
    "hades-tunnel-up", "hades-tunnel-status", "hades-tunnel-down", "codex-local-register",
    "v1-sql-tunnel-up", "v1-sql-tunnel-status", "v1-sql-tunnel-down",
    "v1-license-tunnel-up", "v1-license-tunnel-status", "v1-license-tunnel-down"
  )
  $names | ForEach-Object {
    $command = Get-Command $_ -ErrorAction SilentlyContinue
    if ($command) {
      [pscustomobject]@{ Command = $_; Type = $command.CommandType }
    }
  } | Format-Table -AutoSize
  Write-Host "Run 'aliases' to inspect the complete Windows command surface."
}
function global:cdp { (Get-Location).Path | Set-Clipboard }
function global:fixdock { Stop-Process -Name explorer -Force }
function global:rider { Start-Process "rider64.exe" -ArgumentList $args }
function global:copilot { & copilot.exe @args }
function global:ftp {
  & (Join-Path $script:ForgeWindowsRoot "scripts\ftp.ps1") @args
}
function global:codex-local-register {
  & (Join-Path $script:ForgeWindowsRoot "scripts\codex-local-register.ps1") @args
}
function global:winget-update {
  & (Join-Path $script:ForgeWindowsRoot "scripts\winget-update.ps1") @args
}
function global:drive-fill {
  & (Join-Path $script:ForgeWindowsRoot "scripts\drive-fill.ps1") @args
}
function global:showeth {
  Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceDescription,
    @{Name = "IPv4Address"; Expression = { $_.IPv4Address.IPAddress }}
}
function global:kp {
  param([Parameter(Mandatory, Position = 0)][int]$Port)
  $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
  $processIds = @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
  if ($processIds.Count -eq 0) {
    Write-Host "No process is using TCP port $Port."
    return
  }
  $processIds | ForEach-Object { Stop-Process -Id $_ -Force }
}

function global:info {
  $os = Get-CimInstance Win32_OperatingSystem
  $computer = Get-CimInstance Win32_ComputerSystem
  $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
  [pscustomobject]@{
    Station = $env:COMPUTERNAME
    Windows = $os.Caption
    Version = $os.Version
    Uptime = (Get-Date) - $os.LastBootUpTime
    CPU = $computer.SystemType
    MemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    SystemDriveFreeGB = [math]::Round($systemDrive.FreeSpace / 1GB, 1)
  } | Format-List
}

function global:gs { git status @args }
function global:gco { git checkout @args }
function global:gp { git pull @args }
function global:gfo { git fetch origin @args }
function global:gpu { git push @args }
function global:gb { git branch @args }
function global:dps { docker ps @args }
function global:dcu { docker compose up @args }
function global:dcd { docker compose down @args }
function global:rmc { ssh -t oliver@masterchief @args }
function global:rmcr { ssh -t oliver@masterchief-ts @args }
function global:mcshutdown { ssh -t oliver@masterchief "sudo systemctl poweroff" }
function global:meerkat-enroll { ssh -t vps1 "sudo meerkat-agent enroll --addr vps1.tnisoft.ro:8765" }
function global:pr { patch -R @args }
function global:ttbs {
  Invoke-ForgeBash "C:\work\ardis.timetrack\buildsolution.sh" @args
}
function global:ttbd {
  Invoke-ForgeBash "C:\work\ardis.timetrack\Ardis.Timetrack\build-docker.sh" @args
}

function Clear-ForgeCurrentDirectory {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
  param()
  $current = (Get-Location).Path
  if ($current -in @((Get-Item $HOME).FullName, [System.IO.Path]::GetPathRoot($current))) {
    throw "Refusing to clear unsafe directory: $current"
  }
  if ($PSCmdlet.ShouldProcess($current, "Permanently delete all children")) {
    Get-ChildItem -LiteralPath $current -Force | Remove-Item -Recurse -Force
  }
}
function global:dela { Clear-ForgeCurrentDirectory }
function global:snapdel { snapshots; Clear-ForgeCurrentDirectory }
function global:lcsnapdel { locsnapshots; Clear-ForgeCurrentDirectory }
function global:perflogclean { perflog; Clear-ForgeCurrentDirectory }
function global:screenshotclean {
  Get-ChildItem -LiteralPath (Join-Path $HOME "Desktop") -Filter "*.png" -File |
    Remove-Item -Confirm
}

$locations = @{
  "convo" = "C:\games\convoy-hunter"
  "timetrack" = "C:\work\ardis.timetrack"
  "ttc" = "C:\work\ardis.timetrack\ardis.timetrack.client"
  "ttclient" = "C:\work\ardis.timetrack\ardis.timetrack.client"
  "ttmd" = "C:\work\ardis.timetrack\Ardis.Timetrack.Migrations\Database"
  "perfclient" = "C:\work\ardis-perform\ardis.perform.client"
  "perfdev" = "C:\work\ardis-perform-dev"
  "perf228" = "C:\work\ardis-perform-228"
  "perf230" = "C:\work\ardis-perform-230"
  "perfold" = "C:\work\ardis-perform-older"
  "perfclient230" = "C:\work\ardis-perform-230\ardis.perform.client"
  "gpt" = "C:\work\ardis.tools.extensions"
  "gptbin" = "C:\work\ardis.tools.extensions\Ardis.Utils\bin\debug\net8.0"
  "lc" = "C:\work\ardis-local-connector"
  "localconnector" = "C:\work\ardis-local-connector"
  "fn" = "C:\projects\macos-frontnotes"
  "bl" = "C:\projects\bookinglounge"
  "meerkat" = "C:\projects\meerkat"
  "tally" = "C:\projects\tally"
  "rooted" = "C:\projects\rooted"
  "aiwk" = "C:\projects\alice-in-wonderkitchen"
  "wk" = "C:\projects\alice-in-wonderkitchen"
  "wkdata" = "C:\projects\alice-in-wonderkitchen\wonderkitchen-data"
  "invoice" = (Join-Path $HOME "tni-invoice")
  "perflog" = "C:\work\perform-output\logs\perform"
  "locsql" = (Join-Path $HOME "sql")
  "locsnapshots" = (Join-Path $HOME "sql\snapshots")
  "shared" = "S:\"
  "clients" = "S:\sql\clients"
  "vsql" = "S:\sql"
  "snapshots" = "S:\sql\docker\snapshots"
}
$locations.GetEnumerator() | ForEach-Object {
  Register-ForgeLocation -Name $_.Key -Path $_.Value
}
function global:convo {
  Start-Process "godot-mono" -WorkingDirectory "C:\games\convoy-hunter" -ArgumentList @(
    "--path", "game", "--windowed", "--resolution", "932x430"
  ) + $args
}

$sharedCommands = @{
  "web" = "scripts/web.sh"
  "winappclean" = "scripts/win-shortcut-clean.sh"
  "vpn" = "scripts/vpn.sh"
  "dvpn" = "scripts/dvpn.sh"
  "vpns" = "scripts/vpn-status.sh"
  "eject-all" = "scripts/eject-all.sh"
  "hdd-clean" = "scripts/hdd-clean.sh"
  "al" = "scripts/aliases.sh"
  "workset" = "scripts/work.sh"
  "port-release" = "scripts/port-release.sh"
  "binclear" = "scripts/bin-clear.sh"
  "dotnet-clean" = "scripts/dotnet-clean.sh"
  "switch" = "scripts/git-switch.sh"
  "gpo" = "scripts/git-publish-origin.sh"
  "gbd" = "scripts/branch-delete.sh"
  "gdel" = "scripts/git-del.sh"
  "branch-clean" = "scripts/branch-local-clean.sh"
  "genopenapi" = "scripts/gen-open-api.sh"
  "genopenapitimetrack" = "scripts/gen-open-api-timetrack.sh"
  "ardis-migrate" = "scripts/ardis-migrate.sh"
  "ram" = "scripts/ardis-migrate-remote.sh"
  "ardis-patch" = "scripts/patch.sh"
  "ardis-complete" = "scripts/ardis-complete.sh"
  "perf-cache-reset" = "scripts/perform-cache-reset.sh"
  "publish-tt" = "scripts/publish-tt.sh"
  "publish-te" = "scripts/publish-te.sh"
  "organizer" = "scripts/organizer.sh"
  "clean" = "scripts/clean.sh"
  "present" = "scripts/present.sh"
  "convert-mov" = "scripts/convert-mov.sh"
  "patch" = "scripts/patch.sh"
  "stio" = "scripts/station-io.sh"
  "script-run" = "scripts/script-run.sh"
  "sqlexec" = "scripts/sql-execute.sh"
  "docker-cleanup" = "scripts/docker-cleanup.sh"
  "docker-clean-fact" = "scripts/docker-clean-known-facts.sh"
  "dba" = "scripts/db-admin.sh"
  "dbs" = "scripts/docker-start.sh"
  "dbu" = "scripts/db-upload-bak.sh"
  "dbr" = "scripts/db-restore.sh"
  "db-index" = "scripts/db-index.sh"
  "dbsn" = "scripts/db-snapshot.sh"
  "rdbsn" = "scripts/db-remote-backup.sh"
  "rdbr" = "scripts/db-remote-restore.sh"
  "rdown" = "scripts/db-remote-download.sh"
  "rup" = "scripts/db-remote-upload.sh"
  "dbc" = "scripts/db-clear.sh"
  "dbo" = "scripts/db-optimize.sh"
  "dbfix" = "scripts/db-fix.sh"
  "sdb" = "scripts/switch-db.sh"
  "dwkdata" = "scripts/deploy-wonderkitchen.sh"
  "aiusage" = "scripts/agents/usage.sh"
  "mcsleep" = "scripts/mcsleep.sh"
  "mcboot" = "scripts/mcboot.sh"
  "vps1-status" = "scripts/vps1-status"
  "v1sn" = "scripts/vps1/vps1-db-snapshot.sh"
  "v1r" = "scripts/vps1/vps1-db-restore.sh"
  "v1dbindex" = "scripts/vps1/vps1-db-index.sh"
  "v1down" = "scripts/vps1/vps1-db-download.sh"
  "v1up" = "scripts/vps1/vps1-db-upload.sh"
  "rdown-to-v1" = "scripts/vps1/vps1-db-relay-download.sh"
  "v1drop" = "scripts/vps1/vps1-db-drop.sh"
  "v1sndrop" = "scripts/vps1/vps1-db-snapshot-drop.sh"
  "v1am" = "scripts/vps1/vps1-db-migrate.sh"
  "v1list" = "scripts/vps1/vps1-db-list.sh"
  "v1opt" = "scripts/vps1/vps1-db-optimize.sh"
  "v1-bl-publish" = "scripts/vps1/vps1-bl-publish.sh"
}
$sharedCommands.GetEnumerator() | ForEach-Object {
  Register-ForgeBashCommand -Name $_.Key -Script $_.Value
}

Register-ForgeBashCommand -Name "publish-perf-local" -Script "scripts/perform-local-portainer.sh" -PrefixArguments @("--interactive", "--compose-up")
Register-ForgeBashCommand -Name "workinfo" -Script "scripts/work.sh" -PrefixArguments @("--info")
Register-ForgeBashCommand -Name "v1-sql-up" -Script "scripts/vps1/vps1-db-state.sh" -PrefixArguments @("online")
Register-ForgeBashCommand -Name "v1-sql-down" -Script "scripts/vps1/vps1-db-state.sh" -PrefixArguments @("offline")

function global:hades-tunnel-up {
  & (Join-Path $script:ForgeWindowsRoot "scripts\hades-tunnel.ps1") -Action up
}
function global:hades-tunnel-down {
  & (Join-Path $script:ForgeWindowsRoot "scripts\hades-tunnel.ps1") -Action down
}
function global:hades-tunnel-status {
  & (Join-Path $script:ForgeWindowsRoot "scripts\hades-tunnel.ps1") -Action status
}

$nativeTunnel = Join-Path $script:ForgeWindowsRoot "scripts\vps1-tunnel.ps1"
function Invoke-ForgeTunnel([string]$Name, [string]$Action) {
  & $nativeTunnel -Name $Name -Action $Action
}
foreach ($tunnelName in @("sql", "license", "bl", "meerkat", "tally")) {
  foreach ($action in @("up", "down", "status")) {
    $nameCopy = $tunnelName
    $actionCopy = $action
    $commandName = "v1-$tunnelName-tunnel-$action"
    $body = { Invoke-ForgeTunnel $nameCopy $actionCopy }.GetNewClosure()
    Set-Item -Path "Function:\global:$commandName" -Value $body -Force
  }
}

$aliases = @{
  "inf" = "info"; "prl" = "port-release"; "dnc" = "dotnet-clean"
  "a" = "al"; "ejectall" = "eject-all"; "ea" = "eject-all"
  "hc" = "hdd-clean"; "ws" = "workset"; "wi" = "workinfo"
  "am" = "ardis-migrate"; "ap" = "ardis-patch"; "ac" = "ardis-complete"
  "pcr" = "perf-cache-reset"; "org" = "organizer"; "o" = "organizer"
  "prs" = "present"; "p" = "patch"; "sio" = "stio"
  "sw" = "switch"; "bc" = "branch-clean"; "goa" = "genopenapi"
  "sr" = "script-run"; "se" = "sqlexec"
  "dcl" = "docker-cleanup"; "dcf" = "docker-clean-fact"
  "tt" = "timetrack"; "inv" = "invoice"; "ti" = "invoice"
  "lcsql" = "locsql"; "lcsnaphots" = "locsnapshots"
  "lcsnap" = "locsnapshots"; "lcs" = "locsnapshots"; "snap" = "snapshots"
  "ms" = "mcsleep"; "mcbt" = "mcboot"; "mb" = "mcboot"
  "vps1-snapshot" = "v1sn"; "vps1-restore" = "v1r"
  "vps1-db-index" = "v1dbindex"; "vps1-download" = "v1down"
  "vps1-upload" = "v1up"; "vps1-relay-download" = "rdown-to-v1"
  "vps1-drop" = "v1drop"
  "vps1-snapshot-drop" = "v1sndrop"; "vps1-migrate" = "v1am"
  "vps1-list" = "v1list"; "vps1-optimize" = "v1opt"
  "vps1-sql-up" = "v1-sql-up"; "vps1-sql-down" = "v1-sql-down"
  "vps1-bl-publish" = "v1-bl-publish"
}
$aliases.GetEnumerator() | ForEach-Object { Register-ForgeAlias $_.Key $_.Value }

foreach ($tunnelName in @("sql", "license", "bl", "meerkat", "tally")) {
  foreach ($action in @("up", "down", "status")) {
    Register-ForgeAlias "vps1-$tunnelName-tunnel-$action" "v1-$tunnelName-tunnel-$action"
  }
}
