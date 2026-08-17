@echo off
net session >nul 2>&1
if not %errorlevel%==0 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\restore_official.ps1"
pause
