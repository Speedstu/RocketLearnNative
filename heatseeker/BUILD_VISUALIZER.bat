@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if not exist "RocketSimVis\project.godot" (
  echo ERROR: RocketSimVis\project.godot is missing.
  exit /b 1
)
call "%ROOT%\tools\FIND_GODOT.bat"
if errorlevel 1 exit /b 1
cmake -S . -B build-native -G "Visual Studio 17 2022" -A x64 -DTORCH_ROOT="%ROOT%\third_party\libtorch" -DROCKETSIM_DIR="%ROOT%\third_party\RocketSim"
if errorlevel 1 exit /b 1
cmake --build build-native --config Release --target rocket_learn_visualizer -- /clp:ErrorsOnly
exit /b %errorlevel%
