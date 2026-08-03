$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot 'build-native\bin\Release'
$customRoot = if ($env:RL_RUNTIME_ROOT) { $env:RL_RUNTIME_ROOT } else { 'D:\GigaLearnCPP_GLAZE_DISCRETE' }
if (-not (Test-Path (Join-Path $customRoot 'deps\zluda\zluda.exe'))) { throw 'Custom ZLUDA runtime was not found' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$sources = @(
    (Join-Path $customRoot 'build-cu118\Release'),
    (Join-Path $customRoot 'deps\zluda')
)
foreach ($source in $sources) {
    Get-ChildItem $source -Filter '*.dll' | ForEach-Object {
        $target = Join-Path $destination $_.Name
        if (-not (Test-Path -LiteralPath $target)) {
            try { New-Item -ItemType HardLink -Path $target -Target $_.FullName | Out-Null }
            catch { Copy-Item -LiteralPath $_.FullName -Destination $target }
        }
    }
}
