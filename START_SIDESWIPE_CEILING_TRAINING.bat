@echo off
setlocal
cd /d "%~dp0"
set "PY=%~dp0sideswipe_ceiling\.venv\Scripts\python.exe"
if not exist "%PY%" (
  echo [ERROR] Ceiling environment not installed.
  echo Run SETUP_SIDESWIPE_OMEN_AUTO.bat first.
  pause
  exit /b 2
)
"%PY%" "%~dp0sideswipe_ceiling\ceiling_supervisor.py" --root "%~dp0sideswipe_ceiling"
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="130" echo [INFO] Training stopped safely. Re-run this BAT to resume.
if not "%RC%"=="0" if not "%RC%"=="130" echo [ERROR] Ceiling supervisor exited with %RC%.
if not "%RC%"=="0" pause
exit /b %RC%
