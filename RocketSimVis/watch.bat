@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"

set "PATH=%ROOT%\libtorch\lib;%PATH%"
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.6.3-stable_win64.exe"
set "WATCH_EXE=%ROOT%\target\release\examples\watch.exe"

if exist "%~dp0visualiser\launch.local.bat" call "%~dp0visualiser\launch.local.bat"
if defined GODOT_EXE set "GODOT=%GODOT_EXE%"

if not exist "%ROOT%\libtorch\lib\torch_cuda.dll" (
	echo libtorch was not found at "%ROOT%\libtorch".
	pause
	exit /b 1
)

if not exist "%ROOT%\checkpoints" (
	echo No checkpoints yet, you will be watching an untrained bot.
	echo Run train.bat first if that is not what you wanted.
	echo.
)

if not exist "%WATCH_EXE%" (
	echo watch.exe was not found, building it once...
	cargo build --release --example watch
	if errorlevel 1 (
		echo Build failed.
		pause
		exit /b 1
	)
)

if exist "%GODOT%" (
	echo Starting the visualiser...
	start "rl-arena visualiser" "%GODOT%" --path "%~dp0."
	timeout /t 3 /nobreak >nul
) else (
	echo Godot was not found at "%GODOT%".
	echo Open the visualiser yourself, it listens on UDP 9273.
	echo.
)

"%WATCH_EXE%"

echo.
pause
