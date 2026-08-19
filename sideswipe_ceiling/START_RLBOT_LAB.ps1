param(
  [ValidateSet('Native','Internal','Discover','Diagnose')][string]$Mode='Native',
  [int]$Hz=20
)
$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$Lab=Join-Path $RepoRoot 'sideswipe_one_instance_lab'
$Tools=Join-Path $Lab 'tools'
if (-not (Test-Path $Tools)) { throw "SideSwipe lab missing: $Lab" }
$resolver=Join-Path $Tools 'resolve_best_checkpoint.ps1'
if (-not (Test-Path $resolver)) { throw 'resolve_best_checkpoint.ps1 missing. Run SETUP_SIDESWIPE_OMEN_AUTO.bat.' }
if ($Mode -eq 'Diagnose') {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'diagnose.ps1')
  exit $LASTEXITCODE
}
if ($Mode -eq 'Discover') {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'discover_internal.ps1')
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'validate_profile.ps1')
  exit $LASTEXITCODE
}
$ckpt=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver | Select-Object -Last 1
if (-not $ckpt -or -not (Test-Path $ckpt)) { throw 'Best checkpoint resolution failed.' }
$hash=(Get-FileHash -Algorithm SHA256 $ckpt).Hash.ToLowerInvariant()
Write-Host '============================================================'
Write-Host ' SIDESWIPE RLBOT-LIKE ONE-INSTANCE LAB'
Write-Host '============================================================'
Write-Host "Checkpoint: $ckpt"
Write-Host "SHA256    : $hash"
Write-Host 'Scope     : offline Training/Exhibition/private testing only'
if ($Mode -eq 'Internal') {
  $profile=Join-Path $Lab 'config\runtime_profile.json'
  $ok=$false
  if (Test-Path $profile) {
    try {
      $p=Get-Content $profile -Raw | ConvertFrom-Json
      $ok=[bool]($p.validated -and $p.offline_only -and $p.controls.enabled)
    } catch {}
  }
  if (-not $ok) {
    Write-Warning 'Internal custom-vs-custom is not validated for this installed Sideswipe build.'
    Write-Host 'Running read-only discovery + validation first. If validation remains fail-closed, use the Native shortcut.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'discover_internal.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'validate_profile.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'start_botvbot.ps1') -Blue $ckpt -Orange $ckpt -Hz ([Math]::Max(20,$Hz))
  exit $LASTEXITCODE
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools 'start_policy_vs_native.ps1') -Checkpoint $ckpt -Team 0 -Hz $Hz
exit $LASTEXITCODE
