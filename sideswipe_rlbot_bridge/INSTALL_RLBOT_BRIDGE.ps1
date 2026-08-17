param([string]$Root='D:\RocketLearnNative')
$ErrorActionPreference='Stop'
$src=Split-Path -Parent $MyInvocation.MyCommand.Path
if (!(Test-Path $Root)) { throw "RocketLearnNative root not found: $Root" }
foreach($d in @('cpp','sideswipe','tools')) { New-Item -ItemType Directory -Force (Join-Path $Root $d) | Out-Null }

# The full GC framework patch supplies the base play_main + CMake target. This overlay
# applies the v2 source patch and installs the operational launchers/configuration.
$basePlay=Join-Path $Root 'cpp\sideswipe_play_main.cpp'
$patch=Join-Path $src 'sideswipe_play_v2.patch'
if (!(Test-Path $basePlay)) { throw 'cpp\sideswipe_play_main.cpp missing: apply sideswipe_gc_framework_20260816 first.' }
if (!(Select-String -Quiet -Path $basePlay -Pattern 'FrameSource')) { throw 'Base real-game bridge is too old: apply the GC framework patch first.' }

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git) {
  Push-Location $Root
  try {
    git apply --check --ignore-space-change --ignore-whitespace $patch 2>$null
    if ($LASTEXITCODE -eq 0) { git apply --ignore-space-change --ignore-whitespace $patch; Write-Host '[install] applied C++ bridge v2 patch' }
    elseif (Select-String -Quiet -Path $basePlay -Pattern 'observe_only') { Write-Host '[install] C++ bridge v2 already applied' }
    else { throw 'C++ patch did not apply cleanly.' }
  } finally { Pop-Location }
} elseif (-not (Select-String -Quiet -Path $basePlay -Pattern 'observe_only')) {
  throw 'git.exe is required once to apply the C++ overlay patch.'
}

$copies=@(
 @{from='sideswipe\realgame.ini'; to='sideswipe\realgame.ini'},
 @{from='sideswipe\START_SIDESWIPE_RLBOT.bat'; to='sideswipe\START_SIDESWIPE_RLBOT.bat'},
 @{from='sideswipe\START_SIDESWIPE_RLBOT_OBSERVE.bat'; to='sideswipe\START_SIDESWIPE_RLBOT_OBSERVE.bat'},
 @{from='sideswipe\START_SIDESWIPE_RLBOT_BOTVBOT.bat'; to='sideswipe\START_SIDESWIPE_RLBOT_BOTVBOT.bat'},
 @{from='tools\SETUP_REALGAME.ps1'; to='tools\SETUP_REALGAME.ps1'},
 @{from='tools\DIAGNOSE_SIDESWIPE_RLBOT.ps1'; to='tools\DIAGNOSE_SIDESWIPE_RLBOT.ps1'}
)
foreach($x in $copies) {
  $from=Join-Path $src $x.from; $to=Join-Path $Root $x.to
  if ((Test-Path $to) -and !(Test-Path ($to+'.before-rlbot-v2.bak'))) { Copy-Item $to ($to+'.before-rlbot-v2.bak') -Force }
  Copy-Item $from $to -Force
  Write-Host ('[install] ' + $x.to)
}
$cm=Join-Path $Root 'sideswipe\CMakeLists.txt'
if (!(Test-Path $cm) -or -not (Select-String -Quiet -Path $cm -Pattern 'rocket_sideswipe_play')) {
  throw 'CMake target rocket_sideswipe_play missing: apply the base GC framework patch.'
}
Write-Host '[install] SideSwipe RLBot bridge v2 installed.'
Write-Host "[next] powershell -ExecutionPolicy Bypass -File `"$Root\tools\DIAGNOSE_SIDESWIPE_RLBOT.ps1`""
