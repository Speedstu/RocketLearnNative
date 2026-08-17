param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools\common.ps1')
Ensure-CMake
$libtorch = Join-Path $Root 'tools\libtorch'
if (-not (Test-Path (Join-Path $libtorch 'share\cmake\Torch\TorchConfig.cmake'))) {
    Write-Host '[libtorch] Download PyTorch 2.13.0 CPU Windows...'
    $zip = Join-Path $env:TEMP 'libtorch-2.13.0-cpu.zip'
    Invoke-WebRequest -UseBasicParsing 'https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.13.0%2Bcpu.zip' -OutFile $zip
    $tmp = Join-Path $env:TEMP ('ssbot-libtorch-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Force $zip $tmp
    if (Test-Path $libtorch) { Remove-Item -Recurse -Force $libtorch }
    Move-Item (Join-Path $tmp 'libtorch') $libtorch
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# Visual Studio Build Tools are needed only for this tiny inference host.
$vswhere = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVCTools = $false
if (Test-Path $vswhere) {
    $vc = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    $hasVCTools = [bool]$vc
}
if (-not $hasVCTools) {
    Ensure-Winget
    Write-Host '[install] Visual Studio 2022 Build Tools C++...'
    winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" | Out-Host
}
$build = Join-Path $PSScriptRoot 'build'
cmake -S $PSScriptRoot -B $build -DCMAKE_PREFIX_PATH="$libtorch" -DCMAKE_BUILD_TYPE=Release -A x64 | Out-Host
cmake --build $build --config Release --parallel 2 | Out-Host
$exe = Join-Path $build 'Release\sideswipe_policy_host.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $build 'sideswipe_policy_host.exe' }
if (-not (Test-Path $exe)) { throw 'sideswipe_policy_host.exe non produit.' }
$bin = Join-Path $Root 'bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item -Force $exe (Join-Path $bin 'sideswipe_policy_host.exe')
Copy-Item -Force (Join-Path $libtorch 'lib\*.dll') $bin
Write-Host '[ok] policy host build terminé.'
