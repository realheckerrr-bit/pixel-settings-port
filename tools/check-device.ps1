param(
    [string] $Adb = "adb"
)

$ErrorActionPreference = "Stop"

& $Adb get-state 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No reachable ADB device. Enable USB debugging and authorize this computer." }

$sdk = (& $Adb shell getprop ro.build.version.sdk).Trim()
$abis = (& $Adb shell getprop ro.product.cpu.abilist).Trim()
$settings = (& $Adb shell pm path com.android.settings 2>$null).Trim()
$intelligence = (& $Adb shell pm path com.google.android.settings.intelligence 2>$null).Trim()

Write-Host "Android SDK: $sdk"
Write-Host "ABIs: $abis"
Write-Host "Settings package: $(if ($settings) { $settings } else { 'not installed' })"
Write-Host "Settings Intelligence: $(if ($intelligence) { $intelligence } else { 'not installed' })"

$sdkNumber = 0
if (-not [int]::TryParse($sdk, [ref] $sdkNumber) -or $sdkNumber -lt 37) {
    throw "SettingsGoogle.apk requires Android SDK 37 or newer."
}
if ($abis -notmatch '(^|,)arm64-v8a(,|$)') {
    throw "base.apk contains ARM64 native libraries and this device does not advertise arm64-v8a."
}

Write-Host "PASS: basic SDK and ABI checks passed. Framework, signer, resource, and privileged-permission compatibility still need target-ROM validation." -ForegroundColor Green
