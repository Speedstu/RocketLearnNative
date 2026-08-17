@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_policy_vs_native.ps1" %*
set RC=%ERRORLEVEL%
if not "%RC%"=="0" pause
exit /b %RC%
