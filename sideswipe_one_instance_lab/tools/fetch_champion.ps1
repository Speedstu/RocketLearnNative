param([switch]$Force)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot
$dst=Join-Path $Root 'checkpoints\champion.pt'
$metaDst=Join-Path $Root 'checkpoints\champion.meta.json'
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

  $expected=$null
  if ($asset.PSObject.Properties.Name -contains 'digest' -and $asset.digest) {
    $expected=([string]$asset.digest -replace '^sha256:','').ToLowerInvariant()
  }

  Write-Host '[model] Téléchargement du champion GitHub...'
  $tmp=$dst+'.tmp'
  Invoke-WebRequest -Headers $headers -UseBasicParsing $asset.browser_download_url -OutFile $tmp
  if ((Get-Item $tmp).Length -lt 100000) { throw 'checkpoint téléchargé anormalement petit' }

  $actual=(Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLowerInvariant()
  if ($expected -and $actual -ne $expected) {
    throw "SHA-256 invalide: attendu=$expected obtenu=$actual"
  }

  Move-Item -Force $tmp $dst
  $meta=[ordered]@{
    release_tag='sideswipe-pretrain-latest'
    release_name=$rel.name
    release_updated_at=$rel.updated_at
    asset_name=$asset.name
    asset_size=[int64]$asset.size
    sha256=$actual
    expected_sha256=$expected
    downloaded_at=(Get-Date).ToString('o')
    source='github-release'
  }
  $meta | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $metaDst
  Write-Host "[model] OK SHA256=$actual"
  Write-Output $dst
  exit 0
} catch {
  Remove-Item ($dst+'.tmp') -Force -ErrorAction SilentlyContinue
  foreach($f in $fallbacks) {
    if (Test-Path $f) {
      Write-Warning "Champion final indisponible; fallback local: $f"
      Copy-Item -Force $f $dst
      $actual=(Get-FileHash -Algorithm SHA256 $dst).Hash.ToLowerInvariant()
      [ordered]@{
        sha256=$actual
        downloaded_at=(Get-Date).ToString('o')
        source='local-fallback'
        source_path=$f
      } | ConvertTo-Json | Set-Content -Encoding UTF8 $metaDst
      Write-Output $dst
      exit 0
    }
  }
  throw "Champion cloud indisponible et aucun fallback local disponible. $($_.Exception.Message)"
}
