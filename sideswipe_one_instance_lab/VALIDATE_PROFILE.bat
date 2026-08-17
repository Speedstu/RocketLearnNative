@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\validate_profile.ps1" %*
pause
