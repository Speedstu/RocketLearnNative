@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo  SIDESWIPE COMPLETE SETUP - ONE INSTANCE / GEN2 CHAMPION
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_SIDESWIPE_COMPLETE.ps1"
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
  echo.
  echo [ERREUR] Setup incomplet. Corrige le message ci-dessus puis relance ce fichier.
  pause
)
exit /b %RC%
