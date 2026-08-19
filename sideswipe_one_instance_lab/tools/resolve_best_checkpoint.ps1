param([switch]$ForceCloud)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot
$local=Join-Path $Root 'checkpoints\local_ceiling_champion.pt'
$localMeta=Join-Path $Root 'checkpoints\local_ceiling_champion.meta.json'
if (-not $ForceCloud -and (Test-Path $local) -and (Get-Item $local).Length -gt 100000) {
  if (Test-Path $localMeta) {
    try {
      $m=Get-Content $localMeta -Raw | ConvertFrom-Json
      Write-Host "[model] local ceiling champion SHA256=$($m.sha256)"
    } catch {}
  }
  Write-Output $local
  exit 0
}
$cloud=& (Join-Path $PSScriptRoot 'fetch_champion.ps1') -Force:$ForceCloud | Select-Object -Last 1
if (-not $cloud -or -not (Test-Path $cloud)) { throw 'No usable SideSwipe champion checkpoint found.' }
Write-Output $cloud
