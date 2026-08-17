. (Join-Path $PSScriptRoot 'common.ps1')
$Root = Get-LabRoot
$p = Get-AndroidPaths $Root
New-Item -ItemType Directory -Force -Path $Root,$p.Sdk,(Join-Path $Root 'logs'),(Join-Path $Root 'checkpoints') | Out-Null

Write-Host '=== SideSwipe One-Instance Bot Lab ==='
Write-Host "Root: $Root"
Ensure-Java17
Ensure-Python
Ensure-CMake

# Android command-line tools: resolve the current Google-hosted Windows archive dynamically.
if (-not (Test-Path $p.SdkManager)) {
    Write-Host '[install] Android command-line tools officiels...'
    $repoXml = Join-Path $env:TEMP 'android-repository2-1.xml'
    Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/repository2-1.xml' -OutFile $repoXml
    [xml]$xml = Get-Content $repoXml
    $node = $xml.SelectSingleNode("//*[local-name()='remotePackage' and @path='cmdline-tools;latest']")
    if (-not $node) { throw 'Impossible de résoudre cmdline-tools;latest dans le dépôt Google.' }
    $archives = $node.SelectNodes(".//*[local-name()='archive']")
    $url = $null
    foreach ($a in $archives) {
        $host = $a.SelectSingleNode(".//*[local-name()='host-os']")
        $u = $a.SelectSingleNode(".//*[local-name()='url']")
        if ($host -and $host.InnerText -eq 'windows' -and $u) { $url = 'https://dl.google.com/android/repository/' + $u.InnerText; break }
    }
    if (-not $url) { throw 'Archive Windows Android command-line tools introuvable.' }
    $zip = Join-Path $env:TEMP 'android-commandlinetools.zip'
    Invoke-WebRequest -UseBasicParsing $url -OutFile $zip
    $tmp = Join-Path $env:TEMP ('ssbot-sdk-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Force $zip $tmp
    $latest = Join-Path $p.Sdk 'cmdline-tools\latest'
    if (Test-Path $latest) { Remove-Item -Recurse -Force $latest }
    New-Item -ItemType Directory -Force -Path (Split-Path $latest) | Out-Null
    Move-Item (Join-Path $tmp 'cmdline-tools') $latest
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$env:ANDROID_SDK_ROOT = $p.Sdk
$env:ANDROID_HOME = $p.Sdk
$env:PATH = "$($p.Sdk)\platform-tools;$($p.Sdk)\emulator;$($p.Sdk)\cmdline-tools\latest\bin;$env:PATH"

Write-Host '[install] Android Emulator + API 30 Google APIs x86_64...'
# Android 11 x86_64 is intentional: Google's emulator image supports ARM64 app binaries through native translation.
$packages = @(
  'platform-tools',
  'emulator',
  'platforms;android-30',
  'build-tools;35.0.0',
  'system-images;android-30;google_apis;x86_64'
)
1..40 | ForEach-Object { 'y' } | & $p.SdkManager --sdk_root=$($p.Sdk) --licenses | Out-Null
& $p.SdkManager --sdk_root=$($p.Sdk) @packages | Out-Host

$avdList = & $p.Emulator -list-avds 2>$null
if ($avdList -notcontains $p.AvdName) {
    Write-Host '[install] Création AVD SideSwipeBotLab_API30...'
    'no' | & $p.AvdManager create avd -n $p.AvdName -k 'system-images;android-30;google_apis;x86_64' -d 'pixel_5' --force | Out-Host
}

$avdCfg = Join-Path $env:USERPROFILE ".android\avd\$($p.AvdName).avd\config.ini"
if (Test-Path $avdCfg) {
    $cfg = Get-Content $avdCfg
    $wanted = [ordered]@{
      'hw.ramSize'='6144'; 'hw.cpu.ncore'='6'; 'hw.gpu.enabled'='yes'; 'hw.gpu.mode'='host';
      'hw.lcd.width'='1920'; 'hw.lcd.height'='1080'; 'hw.lcd.density'='420';
      'hw.initialOrientation'='landscape'; 'hw.keyboard'='yes'; 'disk.dataPartition.size'='16G';
      'PlayStore.enabled'='false'; 'fastboot.forceColdBoot'='no'; 'fastboot.forceFastBoot'='yes'
    }
    foreach ($key in $wanted.Keys) {
        $escaped = [regex]::Escape($key)
        $line = "$key=$($wanted[$key])"
        if ($cfg -match "^$escaped=") { $cfg = $cfg -replace "^$escaped=.*$", $line } else { $cfg += $line }
    }
    $cfg | Set-Content -Encoding ASCII $avdCfg
}

# Hypervisor check. Enable WHPX only if acceleration is unavailable.
try {
    $acc = & $p.Emulator -accel-check 2>&1 | Out-String
    Write-Host $acc.Trim()
    if ($LASTEXITCODE -ne 0 -or $acc -match 'not installed|not usable|failed') {
        Write-Host '[install] Activation Windows Hypervisor Platform...'
        Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart | Out-Null
        Write-Warning 'Un redémarrage Windows peut être nécessaire avant le premier lancement de l’émulateur.'
    }
} catch { Write-Warning $_.Exception.Message }

Write-Host '[install] Python Frida tooling...'
& python.exe -m pip install --disable-pip-version-check --upgrade pip frida frida-tools lief | Out-Host

Write-Host '[build] Host d inference LibTorch (72 obs / 16 actions)...'
& (Join-Path $Root 'bridge\build_policy_host.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { throw 'Compilation du policy host échouée.' }

# Start once and configure the guest. This also lets us verify ARM64 translation support.
Start-LabEmulator
$abi = (& $p.Adb shell getprop ro.product.cpu.abilist).Trim()
Write-Host "[emu] ABI list: $abi"
if ($abi -notmatch 'arm64-v8a') {
    Write-Warning 'arm64-v8a n’apparait pas dans abilist. Sideswipe est ARM64; le mode jeu peut échouer sur cette image.'
}

# Install a Frida server matching the Python module version. Internal mode needs root; visual mode does not.
try {
    & (Join-Path $PSScriptRoot 'setup_frida.ps1') -Root $Root
} catch {
    Write-Warning "Mode interne Frida non prêt: $($_.Exception.Message)"
    Write-Host 'Le mode policy-vs-bot natif reste utilisable.'
}

$state = [ordered]@{
  installed_at = (Get-Date).ToString('o')
  root = $Root
  sdk = $p.Sdk
  avd = $p.AvdName
  emulator_api = 30
  emulator_abi = $abi
  sideswipe_package = 'com.Psyonix.RL2D'
  mode = 'one-instance'
}
Save-LabState ([pscustomobject]$state) $Root

Write-Host '[ok] Lab prêt. Aucun APK Sideswipe tiers n’a été téléchargé.'
Write-Host '[next] Lance INSTALL_SIDESWIPE.bat : il ouvre la source officielle Epic dans l’émulateur.'
