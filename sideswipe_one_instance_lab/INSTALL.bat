@echo off
setlocal EnableExtensions
cd /d "%~dp0"
net session >nul 2>&1
if not %errorlevel%==0 (
  echo [SideSwipe Bot Lab] Elevation administrateur...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

echo ============================================================
echo   SIDESWIPE ONE-INSTANCE BOT LAB - FULL INSTALL
echo ============================================================
echo   Android SDK/Emulator + AVD dedie + ADB + Frida + LibTorch
echo   + policy host + installation Epic officielle.
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1"
if errorlevel 1 goto :fail

echo.
echo [2/2] Installation officielle de Rocket League Sideswipe...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_sideswipe.ps1"
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo [OK] Lab installe et configure.
echo - DIAGNOSE.bat                  : verifie tout
echo - DISCOVER_INTERNAL.bat         : scan UE4 read-only dans Exhibition
echo - START_BOTVBOT.bat             : 2 policies custom, 1 instance (apres validation)
echo - START_POLICY_VS_NATIVE.bat    : policy custom vs bot natif, 1 instance
echo ============================================================
pause
exit /b 0

:fail
echo.
echo [ERREUR] Installation incomplete. Lance DIAGNOSE.bat puis relance INSTALL.bat.
pause
exit /b 1
