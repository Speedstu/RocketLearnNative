$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Root=Get-LabRoot; $p=Get-AndroidPaths; Start-LabEmulator
$backup=Join-Path $Root 'backup\official_apks'; $data=Join-Path $Root 'backup\appdata.tar'
if (-not (Test-Path $backup)) { throw 'Backup officiel absent. Réinstalle Sideswipe via INSTALL_SIDESWIPE.bat.' }
$pkg=Get-SideswipePackage
& $p.Adb shell am force-stop $pkg | Out-Null
& $p.Adb uninstall $pkg | Out-Host
$apks=Get-ChildItem $backup -Filter *.apk | ForEach-Object FullName
if (-not $apks) { throw 'Backup APK vide.' }
& $p.Adb install-multiple -r @apks | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Réinstallation des APK officiels échouée.' }
if (Test-Path $data) {
  & $p.Adb push $data /data/local/tmp/ssbot-appdata.tar | Out-Null
  $uid=(& $p.Adb shell stat -c %u "/data/data/$pkg").Trim()
  & $p.Adb shell "rm -rf /data/data/$pkg/*; tar xf /data/local/tmp/ssbot-appdata.tar -C /data/data/$pkg; chown -R $uid`:$uid /data/data/$pkg; restorecon -RF /data/data/$pkg >/dev/null 2>&1 || true" | Out-Null
}
Remove-Item (Join-Path $Root 'config\gadget_backend.json') -Force -ErrorAction SilentlyContinue
& $p.Adb forward --remove tcp:27042 2>$null | Out-Null
Set-LabOffline $false
Write-Host '[ok] Installation officielle restaurée.'
