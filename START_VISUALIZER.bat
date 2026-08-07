@echo off
setlocal
set "ROOT=%~dp0"
set "VIS=%ROOT%RocketSimVis"
cd /d "%ROOT%"

if not exist "%VIS%\RUN.bat" git submodule update --init --recursive
if not exist "%VIS%\RUN.bat" (
  echo ERROR: Python RocketSimVis submodule is missing.
  exit /b 1
)

if not exist "build-native\bin\Release\rocket_learn_visualizer.exe" call "%ROOT%BUILD_VISUALIZER.bat"
if errorlevel 1 exit /b 1

start "RocketSimVis Python" /d "%VIS%" "%VIS%\RUN.bat"
timeout /t 2 /nobreak >nul
start "RocketLearn Python Visualizer Playback" /min "%ROOT%build-native\bin\Release\rocket_learn_visualizer.exe"
