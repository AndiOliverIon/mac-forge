@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vps1-sql-tunnel.ps1" status
