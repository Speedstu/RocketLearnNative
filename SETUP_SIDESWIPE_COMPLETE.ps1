param([switch]$SkipEpicInstall)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Test-Admin {
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $p=New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  if ($SkipEpicInstall) { $args += '-SkipEpicInstall' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join ' ')
  exit
}

$RepoRoot=Split-Path -Parent $PSCommandPath
$Lab=Join-Path $RepoRoot 'sideswipe_one_instance_lab'
$Tools=Join-Path $Lab 'tools'
if (-not (Test-Path $Lab)) { throw "Lab introuvable: $Lab" }

function Step([string]$Name,[scriptblock]$Action) {
  Write-Host ''
  Write-Host ('='*68)
  Write-Host "[SETUP] $Name"
  Write-Host ('='*68)
  & $Action
}

Write-Host '============================================================'
Write-Host ' SIDESWIPE COMPLETE SETUP - ONE INSTANCE / GEN2 CHAMPION'
Write-Host '============================================================'
Write-Host "Repo : $RepoRoot"
Write-Host 'Mode : offline Exhibition / private testing only'

Step '1/6 - Android SDK, emulator, ADB, Frida, LibTorch, policy host' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'install.ps1')
  if ($LASTEXITCODE -ne 0) { throw "install.ps1 a échoué ($LASTEXITCODE)" }
}

if (-not $SkipEpicInstall) {
  Step '2/6 - Epic Games Store + Rocket League Sideswipe officiel' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'install_sideswipe.ps1')
    if ($LASTEXITCODE -ne 0) { throw "install_sideswipe.ps1 a échoué ($LASTEXITCODE)" }
  }
} else {
  Write-Host '[skip] Installation Epic/Sideswipe demandée comme déjà faite.'
}

Step '3/6 - Champion cloud le plus récent + vérification SHA-256' {
  $model=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'fetch_champion.ps1') -Force | Select-Object -Last 1
  if (-not $model -or -not (Test-Path $model)) { throw 'Checkpoint champion absent après téléchargement.' }
  $hash=(Get-FileHash -Algorithm SHA256 $model).Hash.ToLowerInvariant()
  Write-Host "Champion : $model"
  Write-Host "SHA-256  : $hash"
}

Step '4/6 - Vérifications critiques' {
  . (Join-Path $Tools 'common.ps1')
  $Root=Get-LabRoot
  $policy=Join-Path $Root 'bin\sideswipe_policy_host.exe'
  $champ=Join-Path $Root 'checkpoints\champion.pt'
  if (-not (Test-Path $policy)) { throw "Policy host manquant: $policy" }
  if (-not (Test-Path $champ)) { throw "Champion manquant: $champ" }
  Start-LabEmulator
  if (-not (Test-SideswipeInstalled)) {
    throw 'Rocket League Sideswipe n’est pas encore détecté dans l’émulateur. Termine son installation officielle Epic puis relance SETUP_SIDESWIPE_COMPLETE.bat.'
  }
  Write-Host '[ok] policy host'
  Write-Host '[ok] champion'
  Write-Host "[ok] Sideswipe package: $(Get-SideswipePackage)"
}

Step '5/6 - Diagnostic complet' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'diagnose.ps1')
}

Step '6/6 - Raccourcis bureau + état READY' {
  $Desktop=[Environment]::GetFolderPath('Desktop')
  $ws=New-Object -ComObject WScript.Shell
  $shortcuts=[ordered]@{
    'SideSwipe - Bot vs Native.lnk'='START_POLICY_VS_NATIVE.bat'
    'SideSwipe - Discover Internal.lnk'='DISCOVER_INTERNAL.bat'
    'SideSwipe - Validate Profile.lnk'='VALIDATE_PROFILE.bat'
    'SideSwipe - Bot vs Bot Internal.lnk'='START_BOTVBOT.bat'
    'SideSwipe - Diagnose.lnk'='DIAGNOSE.bat'
  }
  foreach($name in $shortcuts.Keys) {
    $bat=Join-Path $Lab $shortcuts[$name]
    if (-not (Test-Path $bat)) { continue }
    $lnk=$ws.CreateShortcut((Join-Path $Desktop $name))
    $lnk.TargetPath=$env:ComSpec
    $lnk.Arguments="/c `"`"$bat`"`""
    $lnk.WorkingDirectory=$Lab
    $lnk.Save()
  }

  $champ=Join-Path $Lab 'checkpoints\champion.pt'
  $meta=Join-Path $Lab 'checkpoints\champion.meta.json'
  $state=[ordered]@{
    ready=$true
    completed_at=(Get-Date).ToString('o')
    repo_root=$RepoRoot
    lab_root=$Lab
    champion=$champ
    champion_sha256=(Get-FileHash -Algorithm SHA256 $champ).Hash.ToLowerInvariant()
    champion_meta=$(if(Test-Path $meta){Get-Content $meta -Raw | ConvertFrom-Json}else{$null})
    one_instance=$true
    safe_mode='offline-exhibition-private-testing'
    custom_vs_native='ready'
    custom_vs_custom='requires_runtime_discovery_and_validated_profile_before_writes'
  }
  $state | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $Lab 'config\complete_setup.json')
  @"
SIDESWIPE BOT LAB READY

Immediate test:
  START_POLICY_VS_NATIVE.bat

For two custom policies in ONE Sideswipe instance:
  1. DISCOVER_INTERNAL.bat while in Training > Exhibition
  2. VALIDATE_PROFILE.bat
  3. START_BOTVBOT.bat only after the profile is validated

The internal control path intentionally stays fail-closed until discovery/validation succeeds on the installed game build.
"@ | Set-Content -Encoding UTF8 (Join-Path $Lab 'SETUP_READY.txt')
}

Write-Host ''
Write-Host '============================================================'
Write-Host '[READY] Setup local terminé.'
Write-Host 'Test immédiat : raccourci "SideSwipe - Bot vs Native"'
Write-Host '2 policies / 1 instance : Discover -> Validate -> Bot vs Bot'
Write-Host '============================================================'
Read-Host 'Entrée pour fermer'
