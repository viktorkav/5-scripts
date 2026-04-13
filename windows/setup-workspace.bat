@echo off
chcp 65001 >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-workspace.ps1" %*
if %ERRORLEVEL% neq 0 pause
