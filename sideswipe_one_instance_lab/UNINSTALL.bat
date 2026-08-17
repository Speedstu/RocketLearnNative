@echo off
setlocal
net session >nul 2>&1
if not %errorlevel%==0 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$r='%~dp0'; . ($r+'tools\common.ps1'); $p=Get-AndroidPaths $r; if(Test-Path $p.AvdManager){ & $p.AvdManager delete avd -n $p.AvdName }; Write-Host '[ok] AVD supprime. Les outils partages Windows (Python/CMake/VS) ne sont pas desinstalles.'"
pause
