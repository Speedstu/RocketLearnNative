@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if not exist "target\release\rocket-learn-supervisor.exe" call "%~dp0BUILD.bat"
if errorlevel 1 exit /b 1
if not exist logs mkdir logs
start "RocketLearn Native Heatseeker" /min "target\release\rocket-learn-supervisor.exe"
echo Native Heatseeker training supervisor started.
