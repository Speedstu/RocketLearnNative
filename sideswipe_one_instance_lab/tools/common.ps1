Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LabRoot {
    param([string]$From = $PSScriptRoot)
    return (Resolve-Path (Join-Path $From '..')).Path
}

function Get-LabState {
    param([string]$Root = (Get-LabRoot))
    $statePath = Join-Path $Root 'config\state.json'
    if (Test-Path $statePath) {
        return Get-Content $statePath -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{}
}

function Save-LabState {
    param([Parameter(Mandatory)]$State, [string]$Root = (Get-LabRoot))
    $statePath = Join-Path $Root 'config\state.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $statePath) | Out-Null
    $State | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $statePath
}

function Get-AndroidPaths {
    param([string]$Root = (Get-LabRoot))
    $sdk = Join-Path $Root 'android-sdk'
    [pscustomobject]@{
        Sdk = $sdk
        Adb = Join-Path $sdk 'platform-tools\adb.exe'
        Emulator = Join-Path $sdk 'emulator\emulator.exe'
        SdkManager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
        AvdManager = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
        AvdName = 'SideSwipeBotLab_API30'
    }
}

function Ensure-Winget {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'winget.exe est requis pour installer automatiquement Java/CMake/Python. Mets Windows App Installer à jour puis relance INSTALL.bat.'
    }
}

function Ensure-Java17 {
    if (Get-Command java.exe -ErrorAction SilentlyContinue) {
        try {
            $v = (& java.exe -version 2>&1 | Select-Object -First 1)
            if ($v) { Write-Host "[ok] Java: $v"; return }
        } catch {}
    }
    Ensure-Winget
    Write-Host '[install] JDK 17...'
    winget install --id Microsoft.OpenJDK.17 --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
    $javaCandidates = @(
        Get-ChildItem 'C:\Program Files\Microsoft\jdk-17*\bin\java.exe' -File -ErrorAction SilentlyContinue
        Get-ChildItem 'C:\Program Files\Eclipse Adoptium\jdk-17*\bin\java.exe' -File -ErrorAction SilentlyContinue
    ) | Sort-Object FullName -Descending
    $java = $javaCandidates | Select-Object -First 1
    if ($java) { $env:PATH = "$(Split-Path $java.FullName);$env:PATH" }
    if (-not (Get-Command java.exe -ErrorAction SilentlyContinue)) {
        throw 'Java 17 introuvable apres installation. Ferme/réouvre le terminal puis relance INSTALL.bat.'
    }
}

function Ensure-Python {
    if (Get-Command python.exe -ErrorAction SilentlyContinue) {
        try { & python.exe -c "import sys; assert sys.version_info >= (3,10)"; return } catch {}
    }
    Ensure-Winget
    Write-Host '[install] Python 3.12...'
    winget install --id Python.Python.3.12 --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $env:PATH = "$(Split-Path $candidate.FullName);$env:PATH" }
    if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) { throw 'Python 3.12 introuvable après installation.' }
}

function Ensure-CMake {
    if (Get-Command cmake.exe -ErrorAction SilentlyContinue) { return }
    Ensure-Winget
    Write-Host '[install] CMake...'
    winget install --id Kitware.CMake --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
    $env:PATH = "C:\Program Files\CMake\bin;$env:PATH"
}

function Start-LabEmulator {
    param([switch]$NoWindow)
    $p = Get-AndroidPaths
    if (-not (Test-Path $p.Emulator)) { throw 'Android Emulator non installé. Lance INSTALL.bat.' }
    $existing = & $p.Adb devices 2>$null | Select-String 'emulator-\d+\s+device'
    if (-not $existing) {
        $args = @(
            '-avd', $p.AvdName,
            '-gpu', 'host',
            '-memory', '6144',
            '-cores', '6',
            '-no-boot-anim',
            '-accel', 'auto',
            '-timezone', 'Europe/Paris'
        )
        if ($NoWindow) { $args += '-no-window' }
        Write-Host "[emu] start $($p.AvdName)..."
        Start-Process -FilePath $p.Emulator -ArgumentList $args -WorkingDirectory (Split-Path $p.Emulator) | Out-Null
    }
    & $p.Adb wait-for-device | Out-Null
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 2
        $boot = (& $p.Adb shell getprop sys.boot_completed 2>$null).Trim()
        if ($boot -eq '1') { break }
    } while ((Get-Date) -lt $deadline)
    if ($boot -ne '1') { throw 'Emulateur non demarre après 4 minutes.' }
    try { & $p.Adb root | Out-Null; Start-Sleep -Seconds 2; & $p.Adb wait-for-device | Out-Null } catch {}
    & $p.Adb shell settings put system accelerometer_rotation 0 | Out-Null
    & $p.Adb shell settings put system user_rotation 1 | Out-Null
    & $p.Adb shell wm size 1920x1080 | Out-Null
    & $p.Adb shell wm density 420 | Out-Null
    & $p.Adb shell settings put global window_animation_scale 0 | Out-Null
    & $p.Adb shell settings put global transition_animation_scale 0 | Out-Null
    & $p.Adb shell settings put global animator_duration_scale 0 | Out-Null
    & $p.Adb shell svc power stayon true | Out-Null
    $marker = Join-Path (Get-LabRoot) 'config\gadget_backend.json'
    if (Test-Path $marker) {
        & $p.Adb shell svc wifi disable | Out-Null
        & $p.Adb shell svc data disable | Out-Null
        Write-Host '[safety] Backend Gadget détecté: réseau Android OFF.'
    }
    Write-Host '[ok] Emulateur prêt.'
}

function Get-SideswipePackage {
    $p = Get-AndroidPaths
    $packages = (& $p.Adb shell pm list packages 2>$null) -replace '^package:', ''
    $candidate = $packages | Where-Object { $_ -match 'Psyonix.*RL2D|RL2D|Sideswipe' } | Select-Object -First 1
    if ($candidate) { return $candidate.Trim() }
    return 'com.Psyonix.RL2D'
}

function Test-SideswipeInstalled {
    $p = Get-AndroidPaths
    $pkg = Get-SideswipePackage
    $out = & $p.Adb shell pm path $pkg 2>$null
    return [bool]($out -match '^package:')
}

function Set-LabOffline {
    param([bool]$Offline = $true)
    $p = Get-AndroidPaths
    if ($Offline) {
        Write-Host '[safety] Réseau Android OFF (mode Exhibition uniquement).'
        & $p.Adb shell svc wifi disable | Out-Null
        & $p.Adb shell svc data disable | Out-Null
    } else {
        & $p.Adb shell svc wifi enable | Out-Null
    }
}
