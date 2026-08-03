$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$log = Get-ChildItem "$root\logs\training-*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $log) { Write-Error "No training log found"; exit 1 }
Get-Content -Wait -Tail 80 $log.FullName
