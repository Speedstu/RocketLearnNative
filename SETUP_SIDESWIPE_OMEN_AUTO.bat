@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo  SIDESWIPE OMEN AUTO SETUP - CUDA FIRST / CPU FALLBACK
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_SIDESWIPE_OMEN_AUTO.ps1"
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
  echo.
  echo [FALLBACK] The CUDA-first setup returned %RC%.
  echo [FALLBACK] Retrying the same resumable setup with CPU LibTorch/PyTorch.
  echo [FALLBACK] Existing downloads/checkpoints are preserved where possible.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_SIDESWIPE_OMEN_AUTO.ps1" -CpuOnly
  set RC=%ERRORLEVEL%
)

echo.
if not "%RC%"=="0" (
  echo [ERROR] Setup still failed with %RC%.
  echo Send me this terminal output and I can patch the exact failing step.
  pause
) else (
  echo [OK] SideSwipe OMEN stack setup completed.
)
exit /b %RC%
