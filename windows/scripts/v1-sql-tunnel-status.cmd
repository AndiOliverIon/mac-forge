@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vps1-tunnel.ps1" -Name sql -Action status
