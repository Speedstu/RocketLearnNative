param([string]$Blue='', [string]$Orange='', [int]$Hz=30)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths
Start-LabEmulator
if (-not (Test-SideswipeInstalled)) { throw 'Sideswipe non installé. Lance INSTALL_SIDESWIPE.bat.' }
$profilePath=Join-Path $Root 'config\runtime_profile.json'
if (-not (Test-Path $profilePath)) { throw 'runtime_profile.json absent. Lance DISCOVER_INTERNAL.bat.' }
$prof=Get-Content $profilePath -Raw | ConvertFrom-Json
if (-not $prof.validated -or -not $prof.offline_only -or -not $prof.controls.enabled) {
  Write-Host '[blocked] Le mode 2 policies custom reste fail-closed tant que le mapping UE4 de TA build n’a pas été validé.'
  Write-Host '[next] Lance DISCOVER_INTERNAL.bat en Exhibition. Le fallback START_POLICY_VS_NATIVE.bat reste disponible.'
  exit 4
}
if (-not $Blue) { $Blue=& (Join-Path $PSScriptRoot 'resolve_best_checkpoint.ps1') | Select-Object -Last 1 }
if (-not $Orange) { $Orange=$Blue }
$gadget=Test-Path (Join-Path $Root 'config\gadget_backend.json')
if ($gadget) {
  $env:SS_FRIDA_TRANSPORT='gadget'; Set-LabOffline $true; & $p.Adb forward tcp:27042 tcp:27042 | Out-Null
} else {
  try { & (Join-Path $PSScriptRoot 'setup_frida.ps1') -Root $Root } catch { throw "Frida interne indisponible: $($_.Exception.Message)" }
  Set-LabOffline $false
}
$pkg=Get-SideswipePackage
& $p.Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host 'Ouvre/démarre Exhibition dans la fenêtre. Le réseau sera coupé avant toute injection.'
Read-Host 'Match prêt -> Entrée'
if (-not $gadget) { Set-LabOffline $true }
try {
  & python.exe (Join-Path $Root 'bridge\orchestrator.py') run --package $pkg --profile $profilePath --blue $Blue --orange $Orange --hz $Hz
  exit $LASTEXITCODE
} finally { if (-not $gadget) { Set-LabOffline $false } }
