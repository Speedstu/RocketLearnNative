param([switch]$Force)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot
$dst=Join-Path $Root 'checkpoints\champion.pt'
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
if ((Test-Path $dst) -and -not $Force) { Write-Output $dst; exit 0 }

$repoRoot=Split-Path $Root -Parent
$fallbacks=@(
  (Join-Path $repoRoot 'checkpoints\sideswipe_from_scratch\latest.pt'),
  'D:\RocketLearnNative\checkpoints\sideswipe_from_scratch\latest.pt'
) | Select-Object -Unique

try {
  $headers=@{'Accept'='application/vnd.github+json'; 'User-Agent'='SideSwipe-OneInstance-Lab'}
  $rel=Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/Speedstu/RocketLearnNative/releases/tags/sideswipe-pretrain-latest'
  $asset=$rel.assets | Where-Object { $_.name -eq 'sideswipe_pretrained_latest.pt' } | Select-Object -First 1
  if (-not $asset) { throw 'release trouvée mais asset champion absent' }
  Write-Host '[model] Téléchargement du champion GitHub...'
  Invoke-WebRequest -Headers $headers -UseBasicParsing $asset.browser_download_url -OutFile ($dst+'.tmp')
  if ((Get-Item ($dst+'.tmp')).Length -lt 100000) { throw 'checkpoint téléchargé anormalement petit' }
  Move-Item -Force ($dst+'.tmp') $dst
  Write-Output $dst
  exit 0
} catch {
  Remove-Item ($dst+'.tmp') -Force -ErrorAction SilentlyContinue
  foreach($f in $fallbacks) {
    if (Test-Path $f) {
      Write-Warning "Champion final pas encore publié; fallback local: $f"
      Copy-Item -Force $f $dst
      Write-Output $dst
      exit 0
    }
  }
  throw "Le champion cloud est encore en training et aucun fallback local n'est disponible. $($_.Exception.Message)"
}
