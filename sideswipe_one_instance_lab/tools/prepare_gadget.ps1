$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths; Start-LabEmulator
if (-not (Test-SideswipeInstalled)) { throw 'Sideswipe officiel doit être installé avant le backend Gadget.' }
Write-Host '=== BACKEND INTERNE ARM64 / OFFLINE ==='
Write-Host 'Cette étape sauvegarde l’installation officielle, re-signe une copie locale et y charge Frida Gadget ARM64.'
Write-Host 'Elle est réversible via RESTORE_OFFICIAL.bat. Le launcher bot coupera le réseau.'
$confirm=Read-Host 'Tape OFFLINE pour continuer'
if ($confirm -ne 'OFFLINE') { Write-Host 'Annulé.'; exit 2 }

Ensure-Java17; Ensure-Python
& python.exe -m pip install --disable-pip-version-check --upgrade lief frida frida-tools | Out-Host
$pkg=Get-SideswipePackage
$backup=Join-Path $Root 'backup'; $orig=Join-Path $backup 'official_apks'; $patched=Join-Path $backup 'patched_unsigned'; $signed=Join-Path $backup 'patched_signed'
New-Item -ItemType Directory -Force -Path $orig,$patched,$signed | Out-Null
Remove-Item (Join-Path $orig '*.apk'),(Join-Path $patched '*.apk'),(Join-Path $signed '*.apk') -Force -ErrorAction SilentlyContinue

Write-Host '[backup] APK officiels...'
$paths=(& $p.Adb shell pm path $pkg) -replace '^package:','' | Where-Object { $_ -match '\.apk$' }
if (-not $paths) { throw 'pm path ne retourne aucun APK.' }
foreach($remote in $paths) { $name=[IO.Path]::GetFileName($remote.Trim()); & $p.Adb pull $remote.Trim() (Join-Path $orig $name) | Out-Host }
Write-Host '[backup] Données app root...'
& $p.Adb root | Out-Null; Start-Sleep 1; & $p.Adb wait-for-device | Out-Null
& $p.Adb shell "rm -f /data/local/tmp/ssbot-appdata.tar; tar cf /data/local/tmp/ssbot-appdata.tar -C /data/data/$pkg . 2>/dev/null || true" | Out-Null
try { & $p.Adb pull /data/local/tmp/ssbot-appdata.tar (Join-Path $backup 'appdata.tar') | Out-Null } catch { Write-Warning 'Backup data non disponible; les APK officiels sont quand même sauvegardés.' }

$ver=(& python.exe -c "import frida; print(frida.__version__)").Trim()
$asset="frida-gadget-$ver-android-arm64.so.xz"; $cache=Join-Path $Root 'tools\cache'; New-Item -ItemType Directory -Force -Path $cache | Out-Null
$xz=Join-Path $cache $asset; $gadget=Join-Path $cache "frida-gadget-$ver-android-arm64.so"
if (-not (Test-Path $gadget)) {
  $url="https://github.com/frida/frida/releases/download/$ver/$asset"; Write-Host "[gadget] $url"
  Invoke-WebRequest -UseBasicParsing $url -OutFile $xz
  & python.exe -c "import lzma,sys,pathlib; pathlib.Path(sys.argv[2]).write_bytes(lzma.open(sys.argv[1],'rb').read())" $xz $gadget
}
$config=Join-Path $cache 'libssbridge.config.so'
'{"interaction":{"type":"listen","address":"127.0.0.1","port":27042,"on_load":"resume"}}' | Set-Content -Encoding UTF8 $config
& python.exe (Join-Path $Root 'tools\patch_gadget_apks.py') --input $orig --output $patched --gadget $gadget --config $config
if ($LASTEXITCODE -ne 0) { throw 'Patch Gadget échoué avant désinstallation; installation officielle intacte.' }

$bt=Join-Path $p.Sdk 'build-tools\35.0.0'; $zipalign=Join-Path $bt 'zipalign.exe'; $apksigner=Join-Path $bt 'apksigner.bat'
if (-not (Test-Path $zipalign) -or -not (Test-Path $apksigner)) { throw 'Android build-tools 35.0.0 absents. Relance INSTALL.bat.' }
$ks=Join-Path $backup 'offline-lab.keystore'; $pass='SideSwipeOfflineLab2026'
if (-not (Test-Path $ks)) {
  & keytool.exe -genkeypair -keystore $ks -storepass $pass -keypass $pass -alias ssbot -keyalg RSA -keysize 3072 -validity 3650 -dname 'CN=SideSwipe Offline Bot Lab,O=Local,C=FR' | Out-Null
}
foreach($apk in Get-ChildItem $patched -Filter *.apk) {
  $aligned=Join-Path $signed $apk.Name
  & $zipalign -f -p 4 $apk.FullName $aligned | Out-Null
  & $apksigner sign --ks $ks --ks-key-alias ssbot --ks-pass "pass:$pass" --key-pass "pass:$pass" $aligned | Out-Null
  & $apksigner verify $aligned | Out-Null
}

$uninstalled=$false
try {
  Write-Host '[install] Passage à la copie locale offline...'
  & $p.Adb shell am force-stop $pkg | Out-Null
  & $p.Adb uninstall $pkg | Out-Host; $uninstalled=$true
  $apks=Get-ChildItem $signed -Filter *.apk | ForEach-Object FullName
  & $p.Adb install-multiple -r @apks | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'install-multiple de la copie Gadget a échoué' }
  $data=Join-Path $backup 'appdata.tar'
  if (Test-Path $data) {
    & $p.Adb push $data /data/local/tmp/ssbot-appdata.tar | Out-Null
    $uid=(& $p.Adb shell stat -c %u "/data/data/$pkg").Trim()
    & $p.Adb shell "rm -rf /data/data/$pkg/*; tar xf /data/local/tmp/ssbot-appdata.tar -C /data/data/$pkg; chown -R $uid`:$uid /data/data/$pkg; restorecon -RF /data/data/$pkg >/dev/null 2>&1 || true" | Out-Null
  }
  Set-LabOffline $true
  & $p.Adb forward tcp:27042 tcp:27042 | Out-Null
  & $p.Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
  Start-Sleep -Seconds 8
  & python.exe -c "import frida; d=frida.get_device_manager().add_remote_device('127.0.0.1:27042'); p=d.enumerate_processes(); assert p, 'no Gadget process'; print('[ok] Gadget ARM64:',[(x.pid,x.name) for x in p])"
  if ($LASTEXITCODE -ne 0) { throw 'Gadget ne répond pas après lancement.' }
  [pscustomobject]@{enabled=$true; prepared_at=(Get-Date).ToString('o'); port=27042; package=$pkg; frida=$ver; network_policy='offline-only'} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $Root 'config\gadget_backend.json')
  Write-Host '[ok] Backend Gadget ARM64 prêt. Réseau Android reste OFF.'
  Write-Host '[next] Lance DISCOVER_INTERNAL.bat puis VALIDATE_PROFILE.bat.'
} catch {
  Write-Warning $_.Exception.Message
  if ($uninstalled) {
    Write-Warning 'Restauration automatique de l’installation officielle...'
    & (Join-Path $PSScriptRoot 'restore_official.ps1')
  }
  throw
}
