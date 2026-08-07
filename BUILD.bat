@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%"

cmake -S . -B build-native -G "Visual Studio 17 2022" -A x64 -DTORCH_ROOT="%ROOT%third_party\libtorch" -DROCKETSIM_DIR="%ROOT%third_party\RocketSim"
if errorlevel 1 exit /b 1

cmake --build build-native --config Release --target rocket_learn_native -- /clp:ErrorsOnly
if errorlevel 1 exit /b 1

if exist "%ROOT%tools\SYNC_ZLUDA_RUNTIME.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\SYNC_ZLUDA_RUNTIME.ps1"
  if errorlevel 1 echo WARNING: ZLUDA runtime sync failed; build itself succeeded.
)

cargo build --release
exit /b %errorlevel%
