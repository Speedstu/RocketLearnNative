@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
cmake -S . -B build-native -G "Visual Studio 17 2022" -A x64 -DTORCH_ROOT="%ROOT%\third_party\libtorch" -DROCKETSIM_DIR="%ROOT%\third_party\RocketSim"
if errorlevel 1 exit /b 1
cmake --build build-native --config Release --target rocket_learn_evaluator -- /clp:ErrorsOnly
exit /b %errorlevel%
