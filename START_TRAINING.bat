@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%"

if not exist "target\release\rocket-learn-supervisor.exe" call "%ROOT%BUILD.bat"
if errorlevel 1 exit /b 1
if not exist logs mkdir logs

start "RocketLearn Native Soccar 2v2" /min "%ROOT%target\release\rocket-learn-supervisor.exe"
echo Native Soccar 2v2 training supervisor started.
