$log = Get-ChildItem (Join-Path $PSScriptRoot '..\logs\kuxir-training-*.log') |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $log) { throw 'No Kuxir training log found.' }
Write-Host "Following $($log.FullName)"
Get-Content -LiteralPath $log.FullName -Wait -Tail 30
