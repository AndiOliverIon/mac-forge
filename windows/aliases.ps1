# Windows PowerShell aliases for the shared mac-forge workspace.

$WindowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-Alias -Name v1-sql-tunnel-up -Value (Join-Path $WindowsRoot "scripts\v1-sql-tunnel-up.cmd")
Set-Alias -Name v1-sql-tunnel-down -Value (Join-Path $WindowsRoot "scripts\v1-sql-tunnel-down.cmd")
Set-Alias -Name v1-sql-tunnel-status -Value (Join-Path $WindowsRoot "scripts\v1-sql-tunnel-status.cmd")

Set-Alias -Name vps1-sql-tunnel-up -Value v1-sql-tunnel-up
Set-Alias -Name vps1-sql-tunnel-down -Value v1-sql-tunnel-down
Set-Alias -Name vps1-sql-tunnel-status -Value v1-sql-tunnel-status
