param(
 [string]$Serial='127.0.0.1:5555',
 [string]$Root=(Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
)
$ErrorActionPreference='Continue'
$adb=Join-Path $Root 'tools\platform-tools\adb.exe'
Write-Host '=== SideSwipe RLBot diagnostics ==='
if (!(Test-Path $adb)) { Write-Host '[FAIL] adb missing'; exit 2 }
& $adb connect $Serial | Out-Null
$state = & $adb -s $Serial get-state 2>$null
if ($state -ne 'device') { Write-Host "[FAIL] $Serial is not an ADB device"; & $adb devices -l; exit 2 }
Write-Host "[OK] ADB: $Serial"
Write-Host ('[info] resolution: ' + ((& $adb -s $Serial shell wm size) -join ' '))
$events = (& $adb -s $Serial shell getevent -pl 2>&1) -join "`n"
if ($events -match 'ABS_MT_POSITION_X' -and $events -match 'ABS_MT_POSITION_Y') { Write-Host '[OK] multitouch event device detected' } else { Write-Host '[WARN] multitouch axes not detected' }
if (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue) { Write-Host '[OK] ffmpeg available (stream backend)' } else { Write-Host '[WARN] ffmpeg missing: screencap fallback only' }
$exe=Join-Path $Root 'build-sideswipe\Release\rocket_sideswipe_play.exe'
if (Test-Path $exe) { Write-Host '[OK] rocket_sideswipe_play.exe built' } else { Write-Host '[WARN] play executable not built yet' }
$ini=Join-Path $Root 'sideswipe\realgame.ini'
if (Test-Path $ini) { Write-Host '[OK] realgame.ini present' } else { Write-Host '[FAIL] realgame.ini missing' }
$tmp=Join-Path $Root 'tmp'; New-Item -ItemType Directory -Force $tmp | Out-Null
$png=Join-Path $tmp 'sideswipe_rlbot_diag.png'
cmd /c "`"$adb`" -s $Serial exec-out screencap -p > `"$png`""
if ((Test-Path $png) -and (Get-Item $png).Length -gt 10000) { Write-Host "[OK] screenshot captured: $png" } else { Write-Host '[FAIL] screenshot capture failed' }
