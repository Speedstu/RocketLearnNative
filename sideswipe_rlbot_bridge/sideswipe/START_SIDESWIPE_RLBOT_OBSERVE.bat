@echo off
setlocal EnableExtensions
set "ROOT=%~dp0..\.."
cd /d "%ROOT%"
set "SERIAL=%~1"
if "%SERIAL%"=="" set "SERIAL=127.0.0.1:5555"
set "TEAM=%~2"
if "%TEAM%"=="" set "TEAM=0"
set "CKPT=%~3"
if "%CKPT%"=="" if exist "%ROOT%\checkpoints\sideswipe_pretrained\latest.pt" set "CKPT=%ROOT%\checkpoints\sideswipe_pretrained\latest.pt"
if "%CKPT%"=="" if exist "%ROOT%\checkpoints\sideswipe_from_scratch\latest.pt" set "CKPT=%ROOT%\checkpoints\sideswipe_from_scratch\latest.pt"
if "%CKPT%"=="" exit /b 2
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\sideswipe_rlbot_bridge\tools\SETUP_REALGAME.ps1" -Root "%ROOT%"
if errorlevel 1 exit /b 1
set "EXE=%ROOT%\build-sideswipe\Release\rocket_sideswipe_play.exe"
if not exist "%EXE%" call "%ROOT%\sideswipe\BUILD_SIDESWIPE.bat"
if errorlevel 1 exit /b 3
"%EXE%" --serial "%SERIAL%" --team %TEAM% --ini "%ROOT%\sideswipe\realgame.ini" --ckpt "%CKPT%" --hz 20 --observe-only --telemetry "%ROOT%\logs\sideswipe_observe_team%TEAM%.csv"
endlocal
