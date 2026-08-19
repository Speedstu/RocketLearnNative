@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_SIDESWIPE_OMEN_AUTO.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo [ERROR] Setup exited with %RC%.
  pause
)
exit /b %RC%
