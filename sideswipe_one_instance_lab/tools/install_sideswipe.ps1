. (Join-Path $PSScriptRoot 'common.ps1')
$ErrorActionPreference='Stop'
$Root=Get-LabRoot
Start-LabEmulator
$p = Get-AndroidPaths
Set-LabOffline $false
if (Test-SideswipeInstalled) {
    Write-Host '[ok] Rocket League Sideswipe est déjà installé.'
    exit 0
}

$official='https://store.epicgames.com/mobile/android'
Write-Host '[Epic] Installation depuis la source officielle Epic uniquement.'
try {
    $ua='Mozilla/5.0 (Linux; Android 11; SideSwipeBotLab) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'
    $r=Invoke-WebRequest -UseBasicParsing -Headers @{'User-Agent'=$ua} $official
    $raw=$r.Content
    $urls=[regex]::Matches($raw,'https?:\\?/\\?/[^"''< >]+?\\.apk(?:\\?[^"''< >]*)?','IgnoreCase') | ForEach-Object {
        ($_.Value -replace '\\/','/') -replace '&amp;','&'
    } | Select-Object -Unique
    $apkUrl=$urls | Where-Object {
        try { ([uri]$_).Host -match 'epicgames|akamaized' } catch { $false }
    } | Select-Object -First 1
    if ($apkUrl) {
        $apk=Join-Path $env:TEMP 'EpicGamesStore-official.apk'
        Write-Host "[Epic] APK officiel résolu: $(([uri]$apkUrl).Host)"
        Invoke-WebRequest -UseBasicParsing -Headers @{'User-Agent'=$ua} $apkUrl -OutFile $apk
        if ((Get-Item $apk).Length -lt 1000000) { throw 'Téléchargement Epic Store anormalement petit.' }
        & $p.Adb install -r $apk | Out-Host
    }
} catch { Write-Warning "Auto-install Epic Store non résolu: $($_.Exception.Message)" }

$epicPkgs=(& $p.Adb shell pm list packages 2>$null) -replace '^package:','' | Where-Object { $_ -match 'epicgames|epicgamesstore' }
if (-not $epicPkgs) {
    Write-Host '[Epic] Ouverture de la page Android officielle dans l’émulateur...'
    & $p.Adb shell am start -a android.intent.action.VIEW -d $official | Out-Host
}
Write-Host ''
Write-Host 'Dans Epic Games Store, connecte ton compte si demandé puis installe Rocket League Sideswipe.'
Write-Host 'Le setup détectera ensuite automatiquement com.Psyonix.RL2D.'
Write-Host 'Aucun APK Sideswipe non officiel n’est téléchargé, stocké ou redistribué.'
Write-Host ''
Read-Host 'Quand Sideswipe est installé, appuie sur Entrée pour vérifier'
if (Test-SideswipeInstalled) {
    Write-Host '[ok] Sideswipe détecté. Tu peux lancer DISCOVER_INTERNAL.bat.'
} else {
    Write-Warning 'Sideswipe pas encore détecté. Termine l’installation Epic puis relance INSTALL_SIDESWIPE.bat.'
}
