@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sideswipe_ceiling\START_RLBOT_LAB.ps1" -Mode Native
set RC=%ERRORLEVEL%
if not "%RC%"=="0" pause
exit /b %RC%
