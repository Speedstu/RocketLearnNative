@echo off
rem Sets GODOT_EXE for callers. GODOT_EXE can also be supplied explicitly.
if defined GODOT_EXE if exist "%GODOT_EXE%" exit /b 0

for %%G in (godot.exe godot4.exe) do (
  for /f "delims=" %%P in ('where %%G 2^>nul') do (
    set "GODOT_EXE=%%P"
    exit /b 0
  )
)

for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
  for %%F in ("%%~fD\Godot*_win64.exe") do (
    if exist "%%~fF" (
      set "GODOT_EXE=%%~fF"
      exit /b 0
    )
  )
)

echo ERROR: Godot 4 was not found. Install GodotEngine.GodotEngine with winget.
exit /b 1
