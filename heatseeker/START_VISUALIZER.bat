@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if not exist "RocketSimVis\project.godot" (
  echo ERROR: RocketSimVis\project.godot is missing.
  exit /b 1
)
if not exist "build-native\bin\Release\rocket_learn_visualizer.exe" call "%~dp0BUILD_VISUALIZER.bat"
if errorlevel 1 exit /b 1
call "%ROOT%\tools\FIND_GODOT.bat"
if errorlevel 1 exit /b 1
start "RocketSimVis - Heatseeker" "%GODOT_EXE%" --path "%ROOT%\RocketSimVis"
timeout /t 2 /nobreak >nul
start "RocketLearn Heatseeker Playback" /min "%ROOT%\build-native\bin\Release\rocket_learn_visualizer.exe"
