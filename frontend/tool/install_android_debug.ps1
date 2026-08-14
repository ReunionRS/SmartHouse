param(
    [string]$DeviceId = "emulator-5554",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$apkPath = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-debug.apk"

if (-not $SkipBuild) {
    & flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter debug build failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "Debug APK not found: $apkPath"
}

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
$adbPath = if ($adbCommand) {
    $adbCommand.Source
} else {
    Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
}

if (-not (Test-Path -LiteralPath $adbPath)) {
    throw "adb was not found. Check the Android SDK installation."
}

Write-Host "Installing APK without clearing application data..."
& $adbPath -s $DeviceId install -r -t $apkPath
if ($LASTEXITCODE -ne 0) {
    throw "adb install failed with exit code $LASTEXITCODE"
}

Write-Host "Updated $DeviceId. Existing SmartHouse session was preserved."
