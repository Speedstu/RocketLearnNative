. (Join-Path $PSScriptRoot 'common.ps1')
Start-LabEmulator
$p = Get-AndroidPaths
Write-Host '[adb] devices:'
& $p.Adb devices -l
