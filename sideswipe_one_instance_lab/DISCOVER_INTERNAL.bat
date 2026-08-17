@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\discover_internal.ps1" %*
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo [!] Discovery non terminee. Lance DIAGNOSE.bat pour le detail.
pause
exit /b %RC%
