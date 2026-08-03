@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if not defined RLK_VIS_STAGE set "RLK_VIS_STAGE=0"
if not exist "build-native\bin\Release\rocket_kuxir_visualizer.exe" call "%~dp0BUILD_KUXIR_VISUALIZER.bat"
if errorlevel 1 exit /b 1

echo.
echo Choisissez le visualizer Kuxir Pinch :
echo   1. RocketSimVis Godot actuel
echo   2. Ancien RocketSimVis Python
choice /C 12 /N /M "Option [1/2] : "
if errorlevel 2 goto python_visualizer

:godot_visualizer
if not exist "%ROOT%\RocketSimVis\project.godot" (
  echo ERROR: RocketSimVis\project.godot est introuvable.
  exit /b 1
)
call "%ROOT%\tools\FIND_GODOT.bat"
if errorlevel 1 exit /b 1
start "RocketSimVis Godot - Kuxir Pinch" "%GODOT_EXE%" --path "%ROOT%\RocketSimVis"
goto start_playback

:python_visualizer
if not exist "%ROOT%\RocketSimVis_python_backup_20260803\src\main.py" (
  echo ERROR: L'ancien RocketSimVis Python est introuvable.
  exit /b 1
)
if not exist "%ROOT%\.venv-rocketsimvis\Scripts\python.exe" (
  echo ERROR: L'environnement Python .venv-rocketsimvis est introuvable.
  exit /b 1
)
start "RocketSimVis Python - Kuxir Pinch" "%ROOT%\.venv-rocketsimvis\Scripts\python.exe" "%ROOT%\RocketSimVis_python_backup_20260803\src\main.py"

:start_playback
timeout /t 2 /nobreak >nul
start "Kuxir Pinch Playback" /min "%ROOT%\build-native\bin\Release\rocket_kuxir_visualizer.exe"
