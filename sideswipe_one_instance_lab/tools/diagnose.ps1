$ErrorActionPreference='Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths
Write-Host '=== SideSwipe One-Instance Lab Diagnostics ==='
Write-Host "Root          : $Root"
Write-Host "SDK           : $(Test-Path $p.Sdk)"
Write-Host "ADB           : $(Test-Path $p.Adb)"
Write-Host "Emulator      : $(Test-Path $p.Emulator)"
if (Test-Path $p.Emulator) { Write-Host "Acceleration  : $((& $p.Emulator -accel-check 2>&1 | Out-String).Trim())" }
try {
  Start-LabEmulator
  Write-Host "Devices       : $((& $p.Adb devices -l | Out-String).Trim())"
  Write-Host "Android       : $((& $p.Adb shell getprop ro.build.version.release).Trim())"
  Write-Host "ABI           : $((& $p.Adb shell getprop ro.product.cpu.abilist).Trim())"
  Write-Host "Root          : $((& $p.Adb shell id).Trim())"
  Write-Host "Sideswipe     : $(Test-SideswipeInstalled) ($(Get-SideswipePackage))"
  Write-Host "Frida server  : $((& $p.Adb shell 'pidof frida-server || true' 2>$null | Out-String).Trim())"
} catch { Write-Warning $_.Exception.Message }
try { Write-Host "Python        : $(& python.exe --version 2>&1)" } catch { Write-Host 'Python        : MISSING' }
try { Write-Host "Frida Python  : $(& python.exe -c 'import frida; print(frida.__version__)' 2>&1)" } catch { Write-Host 'Frida Python  : MISSING' }
Write-Host "Policy host   : $(Test-Path (Join-Path $Root 'bin\sideswipe_policy_host.exe'))"
Write-Host "Champion      : $(Test-Path (Join-Path $Root 'checkpoints\champion.pt'))"
$prof=Join-Path $Root 'config\runtime_profile.json'
if (Test-Path $prof) {
  try { $j=Get-Content $prof -Raw | ConvertFrom-Json; Write-Host "Profile       : validated=$($j.validated) controls=$($j.controls.enabled) offline=$($j.offline_only)" } catch { Write-Warning 'runtime_profile.json invalide' }
} else { Write-Host 'Profile       : MISSING' }
Write-Host '================================================'
