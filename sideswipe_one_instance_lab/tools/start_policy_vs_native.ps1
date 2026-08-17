param([string]$Checkpoint='', [int]$Team=0, [int]$Hz=20)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $repoRoot=Split-Path $Root -Parent; $p=Get-AndroidPaths
Start-LabEmulator
if (-not (Test-SideswipeInstalled)) { throw 'Sideswipe non installé. Lance INSTALL_SIDESWIPE.bat.' }
if (-not $Checkpoint) { $Checkpoint=& (Join-Path $PSScriptRoot 'fetch_champion.ps1') | Select-Object -Last 1 }
& (Join-Path $repoRoot 'sideswipe_rlbot_bridge\INSTALL_RLBOT_BRIDGE.ps1') -Root $repoRoot
$launcher=Join-Path $repoRoot 'sideswipe\START_SIDESWIPE_RLBOT.bat'
if (-not (Test-Path $launcher)) { throw "Launcher vision absent après overlay: $launcher" }
$serial=((& $p.Adb devices | Select-String '^emulator-\d+\s+device' | Select-Object -First 1).Line -split '\s+')[0]
if (-not $serial) { throw 'Serial émulateur introuvable.' }
$pkg=Get-SideswipePackage
Set-LabOffline $false
& $p.Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host ''
Write-Host 'Mode fallback 1 instance: notre policy contrôle la voiture locale; le bot Exhibition natif contrôle l’adversaire.'
Write-Host 'Ouvre Training > Exhibition et démarre le match.'
Read-Host 'Match prêt -> Entrée (réseau coupé ensuite)'
Set-LabOffline $true
try {
  $env:RLS_HZ="$Hz"
  & cmd.exe /c "`"$launcher`" $serial $Team `"$Checkpoint`""
  exit $LASTEXITCODE
} finally { Set-LabOffline $false }
