param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
. (Join-Path $PSScriptRoot 'common.ps1')
$p = Get-AndroidPaths $Root
Start-LabEmulator

$uid = (& $p.Adb shell id).Trim()
if ($uid -notmatch 'uid=0') {
    & $p.Adb root | Out-Host
    Start-Sleep -Seconds 2
    & $p.Adb wait-for-device | Out-Null
    $uid = (& $p.Adb shell id).Trim()
}
if ($uid -notmatch 'uid=0') { throw 'adb root indisponible sur cet AVD.' }

$ver = (& python.exe -c "import frida; print(frida.__version__)" 2>$null).Trim()
if (-not $ver) { throw 'Module Python frida introuvable.' }
$abi = (& $p.Adb shell getprop ro.product.cpu.abi).Trim()
$fridaArch = if ($abi -match 'x86_64') { 'x86_64' } elseif ($abi -match 'arm64') { 'arm64' } else { throw "ABI Frida non supportée: $abi" }
$asset = "frida-server-$ver-android-$fridaArch.xz"
$url = "https://github.com/frida/frida/releases/download/$ver/$asset"
$cache = Join-Path $Root 'tools\cache'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$xz = Join-Path $cache $asset
$bin = Join-Path $cache ("frida-server-$ver-$fridaArch")
if (-not (Test-Path $bin)) {
    Write-Host "[frida] Download $asset"
    Invoke-WebRequest -UseBasicParsing $url -OutFile $xz
    & python.exe -c "import lzma,sys,pathlib; pathlib.Path(sys.argv[2]).write_bytes(lzma.open(sys.argv[1],'rb').read())" $xz $bin
}
& $p.Adb push $bin /data/local/tmp/frida-server | Out-Host
& $p.Adb shell chmod 755 /data/local/tmp/frida-server | Out-Null
& $p.Adb shell "pkill -f frida-server >/dev/null 2>&1 || true; nohup /data/local/tmp/frida-server >/data/local/tmp/frida.log 2>&1 &" | Out-Null
Start-Sleep -Seconds 1
& python.exe -c "import frida; print('[ok] frida devices:', [d.id for d in frida.enumerate_devices()])"
