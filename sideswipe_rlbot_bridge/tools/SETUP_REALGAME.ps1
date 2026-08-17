param(
  [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$SkipFfmpeg
)
$ErrorActionPreference='Stop'
$tools = Join-Path $Root 'tools'
$pt = Join-Path $tools 'platform-tools'
$adb = Join-Path $pt 'adb.exe'
New-Item -ItemType Directory -Force -Path $tools | Out-Null

if (!(Test-Path $adb)) {
  Write-Host '[setup] Android platform-tools missing; downloading official Google package...'
  $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
  Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
  $tmp = Join-Path $env:TEMP ('rls-pt-' + [guid]::NewGuid().ToString('N'))
  Expand-Archive -Force $zip $tmp
  if (Test-Path $pt) { Remove-Item -Recurse -Force $pt }
  Move-Item (Join-Path $tmp 'platform-tools') $pt
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$env:Path = "$pt;$env:Path"
& $adb start-server | Out-Null

if (!$SkipFfmpeg -and !(Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)) {
  Write-Host '[setup] FFmpeg missing. Trying winget (Gyan.FFmpeg)...'
  if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    winget install --id Gyan.FFmpeg --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
  }
}

foreach ($endpoint in @('127.0.0.1:5555','127.0.0.1:5565')) {
  try { & $adb connect $endpoint | Out-Null } catch {}
}

Write-Host '[setup] adb devices:'
& $adb devices -l
if (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue) {
  Write-Host ('[setup] ffmpeg: ' + (& ffmpeg.exe -version | Select-Object -First 1))
} else {
  Write-Warning 'FFmpeg not found. Bridge will fall back to slower adb screencap mode.'
}
Write-Host '[setup] real-game bridge prerequisites ready.'
