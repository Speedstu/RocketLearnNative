param([int]$Limit=400)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths
Start-LabEmulator
if (-not (Test-SideswipeInstalled)) { throw 'Sideswipe non installé. Lance INSTALL_SIDESWIPE.bat.' }
$gadget=Test-Path (Join-Path $Root 'config\gadget_backend.json')
if ($gadget) {
  $env:SS_FRIDA_TRANSPORT='gadget'; Set-LabOffline $true; & $p.Adb forward tcp:27042 tcp:27042 | Out-Null
} else {
  Set-LabOffline $false
  try { & (Join-Path $PSScriptRoot 'setup_frida.ps1') -Root $Root } catch { throw "Frida interne indisponible: $($_.Exception.Message)" }
}
$pkg=Get-SideswipePackage
Write-Host '[game] Lancement Sideswipe...'
& $p.Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host ''
Write-Host 'IMPORTANT: ouvre Training > Exhibition et démarre un match bot dans la fenêtre Sideswipe.'
Write-Host 'Le scan est READ-ONLY: aucune commande n’est écrite dans le jeu.'
Read-Host 'Quand la balle et les voitures sont visibles, appuie sur Entrée'
if (-not $gadget) { Set-LabOffline $true }
try {
  & python.exe (Join-Path $Root 'bridge\orchestrator.py') discover --package $pkg --limit $Limit
  if ($LASTEXITCODE -ne 0) { throw "Discovery exit code $LASTEXITCODE" }
} finally { if (-not $gadget) { Set-LabOffline $false } }
Write-Host '[ok] Consulte logs\discovery.json et config\runtime_profile.suggested.json.'
