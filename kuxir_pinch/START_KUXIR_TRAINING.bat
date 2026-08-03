@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if not exist "target\release\rocket-kuxir-supervisor.exe" call "%~dp0BUILD_KUXIR.bat"
if errorlevel 1 exit /b 1
if not exist logs mkdir logs
start "RocketLearn Native Kuxir Pinch" /min "target\release\rocket-kuxir-supervisor.exe"
echo Native Kuxir Pinch training supervisor started.
