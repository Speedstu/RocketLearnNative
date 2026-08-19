param(
  [switch]$SkipEpicInstall,
  [switch]$NoTrainingStart,
  [switch]$CpuOnly
)
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
  if ($NoTrainingStart) { $args += '-NoTrainingStart' }
  if ($CpuOnly) { $args += '-CpuOnly' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join ' ')
  exit
}

$RepoRoot=Split-Path -Parent $PSCommandPath
$Lab=Join-Path $RepoRoot 'sideswipe_one_instance_lab'
$LabTools=Join-Path $Lab 'tools'
$Ceiling=Join-Path $RepoRoot 'sideswipe_ceiling'
$Venv=Join-Path $Ceiling '.venv'
$Py=Join-Path $Venv 'Scripts\python.exe'
$Chunks=Join-Path $RepoRoot 'cloud_sideswipe\chunks'
$Source=Join-Path $Ceiling 'src'
$Build=Join-Path $Ceiling 'build'
$Bin=Join-Path $Ceiling 'bin'
$Checkpoints=Join-Path $Ceiling 'checkpoints'
$ExpectedSourceSha='6cfdcbee20581df966805f080437ffe533dd3b51676418b881ee7baf2342b96d'

function Step([string]$Name,[scriptblock]$Action) {
  Write-Host ''
  Write-Host ('='*74)
  Write-Host "[AUTO] $Name"
  Write-Host ('='*74)
  & $Action
}
function Ensure-WingetLocal {
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget.exe is required for the automatic setup.' }
}
function Ensure-BaseTools {
  Ensure-WingetLocal
  if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
  }
  if (-not (Get-Command cmake.exe -ErrorAction SilentlyContinue)) {
    winget install --id Kitware.CMake --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
  }
  if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    winget install --id Python.Python.3.12 --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
  }
  $vswhere="$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
  $hasVC=$false
  if (Test-Path $vswhere) {
    $vc=& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    $hasVC=[bool]$vc
  }
  if (-not $hasVC) {
    winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" | Out-Host
  }
}
function Refresh-Path {
  $machine=[Environment]::GetEnvironmentVariable('Path','Machine')
  $user=[Environment]::GetEnvironmentVariable('Path','User')
  $env:Path="$machine;$user"
}
function Reconstruct-VerifiedSource {
  if (-not (Test-Path $Chunks)) { throw "Source chunks missing: $Chunks" }
  $parts=Get-ChildItem $Chunks -Filter 'part_*.b64' | Sort-Object Name
  if ($parts.Count -lt 2) { throw 'SideSwipe source chunks are incomplete.' }
  $sb=New-Object Text.StringBuilder
  foreach($p in $parts) { [void]$sb.Append((Get-Content $p.FullName -Raw).Trim()) }
  $tar=Join-Path $env:TEMP 'sideswipe_verified_src.tar.gz'
  [IO.File]::WriteAllBytes($tar,[Convert]::FromBase64String($sb.ToString()))
  $actual=(Get-FileHash -Algorithm SHA256 $tar).Hash.ToLowerInvariant()
  if ($actual -ne $ExpectedSourceSha) { throw "Source SHA256 mismatch: expected=$ExpectedSourceSha actual=$actual" }
  if (Test-Path $Source) { Remove-Item -Recurse -Force $Source }
  New-Item -ItemType Directory -Force -Path $Source | Out-Null
  & tar.exe -xzf $tar -C $Source
  if ($LASTEXITCODE -ne 0) { throw 'Verified source extraction failed.' }
  Write-Host "[source] verified SHA256=$actual"
}
function Install-TorchRuntime {
  if (-not (Test-Path $Py)) {
    python.exe -m venv $Venv
    if ($LASTEXITCODE -ne 0) { throw 'Python venv creation failed.' }
  }
  & $Py -m pip install --disable-pip-version-check --upgrade pip wheel setuptools | Out-Host
  if ($CpuOnly) {
    & $Py -m pip install --disable-pip-version-check --upgrade 'torch==2.13.0' --index-url 'https://download.pytorch.org/whl/cpu' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'PyTorch 2.13 CPU install failed.' }
    return
  }
  $ok=$false
  foreach($channel in @('cu130','cu126')) {
    Write-Host "[torch] trying PyTorch 2.13.0 $channel..."
    & $Py -m pip install --disable-pip-version-check --upgrade --force-reinstall 'torch==2.13.0' --index-url "https://download.pytorch.org/whl/$channel" | Out-Host
    if ($LASTEXITCODE -eq 0) {
      $probe=& $Py -c "import torch; print(int(torch.cuda.is_available())); print(torch.__version__); print(torch.version.cuda)" 2>$null
      Write-Host ($probe -join [Environment]::NewLine)
      if (($probe | Select-Object -First 1) -eq '1') { $ok=$true; break }
    }
  }
  if (-not $ok) {
    Write-Warning 'CUDA PyTorch could not be activated. Falling back to CPU so setup remains usable.'
    & $Py -m pip install --disable-pip-version-check --upgrade --force-reinstall 'torch==2.13.0' --index-url 'https://download.pytorch.org/whl/cpu' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'PyTorch CPU fallback install failed.' }
  }
}
function Build-CeilingTrainer {
  & $Py (Join-Path $Ceiling 'patch_source.py') --src $Source | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'Source contract/portable-CUDA patch failed.' }
  $TorchPrefix=(& $Py -c "import torch; print(torch.utils.cmake_prefix_path)").Trim()
  if (-not $TorchPrefix) { throw 'Unable to resolve torch CMake prefix.' }
  if (Test-Path $Build) { Remove-Item -Recurse -Force $Build }
  New-Item -ItemType Directory -Force -Path $Build,$Bin | Out-Null
  & cmake.exe -S $Source -B $Build -DCMAKE_PREFIX_PATH="$TorchPrefix" -DCMAKE_BUILD_TYPE=Release -A x64 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }
  & cmake.exe --build $Build --config Release --parallel 2 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'SideSwipe trainer/evaluator build failed.' }
  $train=Get-ChildItem $Build -Recurse -Filter 'sideswipe_train.exe' | Select-Object -First 1
  $eval=Get-ChildItem $Build -Recurse -Filter 'sideswipe_eval.exe' | Select-Object -First 1
  if (-not $train -or -not $eval) { throw 'sideswipe_train.exe or sideswipe_eval.exe was not produced.' }
  Copy-Item -Force $train.FullName (Join-Path $Bin 'sideswipe_train.exe')
  Copy-Item -Force $eval.FullName (Join-Path $Bin 'sideswipe_eval.exe')
  $torchLib=(& $Py -c "import pathlib,torch; print(pathlib.Path(torch.__file__).parent/'lib')").Trim()
  if (Test-Path $torchLib) { Copy-Item -Force (Join-Path $torchLib '*.dll') $Bin -ErrorAction SilentlyContinue }
}
function Seed-CeilingChampion {
  New-Item -ItemType Directory -Force -Path $Checkpoints | Out-Null
  $dst=Join-Path $Checkpoints 'champion.pt'
  if ((Test-Path $dst) -and (Test-Path (Join-Path $Checkpoints 'champion.meta.json'))) {
    try {
      $m=Get-Content (Join-Path $Checkpoints 'champion.meta.json') -Raw | ConvertFrom-Json
      if ($m.source -eq 'local-ceiling-supervisor') {
        Write-Host '[model] preserving locally promoted ceiling champion.'
        return
      }
    } catch {}
  }
  $cloud=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LabTools 'fetch_champion.ps1') -Force | Select-Object -Last 1
  if (-not $cloud -or -not (Test-Path $cloud)) { throw 'Unable to obtain rolling cloud champion.' }
  Copy-Item -Force $cloud $dst
  $hash=(Get-FileHash -Algorithm SHA256 $dst).Hash.ToLowerInvariant()
  [ordered]@{source='cloud-seed';sha256=$hash;seeded_at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $Checkpoints 'champion.meta.json')
  Write-Host "[model] ceiling seed SHA256=$hash"
}
function Test-TrainerContract {
  $champ=Join-Path $Checkpoints 'champion.pt'
  $eval=Join-Path $Bin 'sideswipe_eval.exe'
  $env:PATH="$Bin;$env:PATH"
  & $eval --candidate $champ --opponent $champ --episodes 24 --team-size 1 --seed 2026300001 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw '1v1 champion self-test failed.' }
  & $eval --candidate $champ --opponent $champ --episodes 16 --team-size 2 --seed 2026300002 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw '2v2 champion self-test failed.' }
}
function Install-Shortcuts {
  $Desktop=[Environment]::GetFolderPath('Desktop')
  $ws=New-Object -ComObject WScript.Shell
  $items=[ordered]@{
    'SideSwipe - Ceiling Training.lnk'='START_SIDESWIPE_CEILING_TRAINING.bat'
    'SideSwipe - RLBot Lab.lnk'='START_SIDESWIPE_RLBOT_LAB.bat'
    'SideSwipe - RLBot BotVsBot Internal.lnk'='START_SIDESWIPE_RLBOT_BOTVBOT.bat'
  }
  foreach($name in $items.Keys) {
    $target=Join-Path $RepoRoot $items[$name]
    if (-not (Test-Path $target)) { continue }
    $lnk=$ws.CreateShortcut((Join-Path $Desktop $name))
    $lnk.TargetPath=$target
    $lnk.WorkingDirectory=$RepoRoot
    $lnk.Save()
  }
}

Write-Host '=============================================================================='
Write-Host ' SIDESWIPE OMEN AUTO SETUP | TRAINING + CURRICULUM + ONE-INSTANCE RLBOT LAB'
Write-Host '=============================================================================='
Write-Host "Repo: $RepoRoot"
Write-Host 'Safety scope: offline Training/Exhibition/private controlled testing only.'
Write-Host 'Truth: plateau is measured statistically for the current 72-observation/16-action contract; theoretical game skill ceiling is not guaranteed.'
New-Item -ItemType Directory -Force -Path $Ceiling,$Bin,$Checkpoints,(Join-Path $Ceiling 'state'),(Join-Path $Ceiling 'runs') | Out-Null

Step '1/8 - Base Windows build tools' {
  Ensure-BaseTools
  Refresh-Path
}
Step '2/8 - One-instance Android/Sideswipe lab dependencies' {
  if (-not (Test-Path (Join-Path $LabTools 'install.ps1'))) { throw "Lab installer missing: $LabTools" }
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LabTools 'install.ps1')
    if ($LASTEXITCODE -ne 0) { throw "lab install rc=$LASTEXITCODE" }
  } catch {
    Write-Warning "Lab base install did not fully finish: $($_.Exception.Message)"
    Write-Warning 'Training setup will continue. A Windows hypervisor reboot may be required before the emulator lab works.'
  }
}
if (-not $SkipEpicInstall) {
  Step '3/8 - Official Epic Games Store / Rocket League Sideswipe' {
    Write-Host 'This step uses the official Epic flow. Account login/consent cannot be automated safely.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LabTools 'install_sideswipe.ps1')
    if ($LASTEXITCODE -ne 0) { Write-Warning "Official Sideswipe install not completed (rc=$LASTEXITCODE). Lab can be finished later without rebuilding the trainer." }
  }
} else { Write-Host '[skip] Official Epic/Sideswipe install skipped by parameter.' }
Step '4/8 - Python/PyTorch 2.13 runtime, CUDA-first' { Install-TorchRuntime }
Step '5/8 - Reconstruct SHA-verified SideSwipe source + enforce 16-action contract' {
  Reconstruct-VerifiedSource
  & $Py (Join-Path $Ceiling 'patch_source.py') --src $Source | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'Verified source contract patch failed.' }
}
Step '6/8 - Build local trainer/evaluator + seed current champion' {
  Build-CeilingTrainer
  Seed-CeilingChampion
  Test-TrainerContract
}
Step '7/8 - Wire the best local champion into the RLBot-like lab' {
  $resolver=Join-Path $LabTools 'resolve_best_checkpoint.ps1'
  if (-not (Test-Path $resolver)) { throw "Best-checkpoint resolver missing: $resolver" }
  Install-Shortcuts
}
Step '8/8 - Write resumable READY state' {
  $champ=Join-Path $Checkpoints 'champion.pt'
  $torchProbe=& $Py -c "import torch,json; print(json.dumps({'version':torch.__version__,'cuda_available':torch.cuda.is_available(),'cuda':torch.version.cuda,'gpu':torch.cuda.get_device_name(0) if torch.cuda.is_available() else None}))"
  $ready=[ordered]@{
    ready=$true
    completed_at=(Get-Date).ToString('o')
    repo_root=$RepoRoot
    ceiling_root=$Ceiling
    champion=$champ
    champion_sha256=(Get-FileHash -Algorithm SHA256 $champ).Hash.ToLowerInvariant()
    torch=($torchProbe | ConvertFrom-Json)
    contract=[ordered]@{observations=72;actions=16;tick_skip=6;transfer_safe=$true}
    curriculum='adaptive candidate curriculum + conservative promotion + ceiling-search plateau gate'
    plateau_rule='two consecutive complete search generations with no statistically confirmed promotion'
    lab_default='one custom policy vs native Exhibition bot, one Sideswipe instance'
    lab_internal='custom-vs-custom remains fail-closed until runtime profile validates current installed build'
    scope='offline-training-exhibition-private-testing-only'
  }
  $ready | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $Ceiling 'SETUP_READY.json')
  @"
SIDESWIPE OMEN AUTO SETUP READY

Training:
  START_SIDESWIPE_CEILING_TRAINING.bat
  - resumes safely from state/checkpoints
  - never promotes without conservative 1v1 + 2v2 gates
  - stops after a statistically verified plateau for the current 72obs/16action contract

RLBot-like real-game lab:
  START_SIDESWIPE_RLBOT_LAB.bat
  - one real Sideswipe emulator instance
  - best available local champion controls the local car
  - native Exhibition bot is the robust default opponent

Custom-vs-custom internal:
  START_SIDESWIPE_RLBOT_BOTVBOT.bat
  - read-only discover/validate first
  - writes remain fail-closed until your installed Sideswipe build is validated

Manual steps that cannot safely be removed:
  - Epic account login / official Sideswipe installation if not already installed
  - starting/opening the Exhibition match before control begins
"@ | Set-Content -Encoding UTF8 (Join-Path $Ceiling 'README_READY.txt')
}
Write-Host ''
Write-Host '=============================================================================='
Write-Host '[READY] SideSwipe OMEN stack prepared.'
Write-Host 'Training shortcut : SideSwipe - Ceiling Training'
Write-Host 'Lab shortcut      : SideSwipe - RLBot Lab'
Write-Host 'Internal 2-policy : SideSwipe - RLBot BotVsBot Internal'
Write-Host '=============================================================================='
if (-not $NoTrainingStart) {
  Write-Host '[launch] Starting ceiling curriculum in a separate terminal...'
  Start-Process cmd.exe -ArgumentList '/k',('"'+(Join-Path $RepoRoot 'START_SIDESWIPE_CEILING_TRAINING.bat')+'"') -WorkingDirectory $RepoRoot
}
