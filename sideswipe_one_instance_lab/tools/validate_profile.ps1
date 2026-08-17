param([int]$Seconds=12)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths
Start-LabEmulator
if (-not (Test-SideswipeInstalled)) { throw 'Sideswipe non installé.' }
$pkg=Get-SideswipePackage
$gadget=Test-Path (Join-Path $Root 'config\gadget_backend.json')
if ($gadget) { $env:SS_FRIDA_TRANSPORT='gadget'; Set-LabOffline $true; & $p.Adb forward tcp:27042 tcp:27042 | Out-Null } else { Set-LabOffline $false }
& $p.Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host 'Démarre un match Exhibition, puis reviens ici.'
Read-Host 'Match en mouvement -> Entrée'
if (-not $gadget) { Set-LabOffline $true }
try {
  & python.exe (Join-Path $Root 'bridge\validate_profile.py') --package $pkg --profile (Join-Path $Root 'config\runtime_profile.json') --seconds $Seconds
  exit $LASTEXITCODE
} finally { if (-not $gadget) { Set-LabOffline $false } }
