@echo off
setlocal EnableExtensions
set "ROOT=%~dp0..\.."
cd /d "%ROOT%"
set "BLUE=%~1"
set "ORANGE=%~2"
if "%BLUE%"=="" set "BLUE=127.0.0.1:5555"
if "%ORANGE%"=="" set "ORANGE=127.0.0.1:5565"
if "%RLS_HZ%"=="" set "RLS_HZ=20"
set "CKPT=%RLS_SIDESWIPE_CKPT%"
if "%CKPT%"=="" if exist "%ROOT%\checkpoints\sideswipe_pretrained\latest.pt" set "CKPT=%ROOT%\checkpoints\sideswipe_pretrained\latest.pt"
if "%CKPT%"=="" if exist "%ROOT%\checkpoints\sideswipe_from_scratch\latest.pt" set "CKPT=%ROOT%\checkpoints\sideswipe_from_scratch\latest.pt"
if "%CKPT%"=="" exit /b 2
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\sideswipe_rlbot_bridge\tools\SETUP_REALGAME.ps1" -Root "%ROOT%"
if errorlevel 1 exit /b 1
set "EXE=%ROOT%\build-sideswipe\Release\rocket_sideswipe_play.exe"
if not exist "%EXE%" call "%ROOT%\sideswipe\BUILD_SIDESWIPE.bat"
if errorlevel 1 exit /b 3

echo Open the same PRIVATE 1v1 match on both emulator instances.
echo Blue=%BLUE% Orange=%ORANGE% Model=%CKPT%
pause
start "SIDESWIPE RLBOT BLUE" cmd /k ""%EXE%" --serial "%BLUE%" --team 0 --ini "%ROOT%\sideswipe\realgame.ini" --ckpt "%CKPT%" --hz %RLS_HZ% --telemetry "%ROOT%\logs\sideswipe_rlbot_blue.csv""
timeout /t 2 /nobreak >nul
start "SIDESWIPE RLBOT ORANGE" cmd /k ""%EXE%" --serial "%ORANGE%" --team 1 --ini "%ROOT%\sideswipe\realgame.ini" --ckpt "%CKPT%" --hz %RLS_HZ% --telemetry "%ROOT%\logs\sideswipe_rlbot_orange.csv""
endlocal
