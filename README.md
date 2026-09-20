# Pixel Settings SDK 37 port

This repository contains the paired APKs supplied for the SDK 37 Pixel Settings build and small tools for checking whether a rooted/custom-ROM device can host them.

This is not a normal APK sideload and it is not a universal Android port. The supplied Settings APK is a system application that replaces the package `com.android.settings`, requests privileged permissions, and has a minimum SDK of 37. A device must have a compatible Android 17/API 37 framework, matching platform/system integration, and an accepted signing key. The companion service also contains ARM64 native libraries.

## Android version compatibility

| Device SDK | Result |
| ---: | --- |
| 34–36 | Not installable as supplied. Lowering only `minSdkVersion` is not a working port. |
| 37+ | Potentially compatible only with a matching framework, platform key, resources, and privileged-app integration. |

Making this work on SDK 34–36 would require a real backport: decompile/rebuild the app, replace or guard API 37 calls, adapt framework/resource references and permissions, rebuild the companion service, sign with the target ROM's accepted platform key, and test each ROM. The APK files alone do not provide the source or the target framework needed to do that safely.

## Included files

| File | Package | SDK | Size |
| --- | --- | --- | ---: |
| `SettingsGoogle.apk` | `com.android.settings` | min/target 37 | 98,044,590 bytes |
| `base.apk` | `com.google.android.settings.intelligence` | min 28 / target 37 | 20,636,332 bytes |

The provided APK is not packaged as `com.android.pixelsettings`; its manifest package is `com.android.settings`. Renaming that package is not a safe manifest-only edit because the APK contains package references, privileged integrations, and signed resources.

## Before attempting an install

1. Make a full boot and data backup. Replacing Settings can leave a device without a usable Settings UI or cause a boot failure.
2. Use `tools/check-device.sh` from an ADB root shell, or `tools/check-device.ps1` from Windows.
3. Do not use `adb install` for this pair. The Settings APK is intended for system/priv-app integration, not ordinary user installation.
4. Confirm that the target ROM is API 37 or newer, ARM64, and already has the required Google/Android framework components.
5. Confirm the target ROM accepts the APK signer for `com.android.settings`. A different platform key normally prevents replacement of the stock Settings package.

The checks are deliberately advisory: passing them does not prove that a ROM's framework, resource IDs, overlays, permissions allowlist, or platform certificate are compatible.

## Verification

The expected SHA-256 values are in [`SHA256SUMS`](SHA256SUMS). The manifest inspection helpers are:

```powershell
.\tools\inspect-apk.ps1 -Apk .\SettingsGoogle.apk, .\base.apk
```

```sh
sha256sum -c SHA256SUMS
```

## Status

This is an APK-level port bundle, not a source rebuild. With only the edited APKs available, supporting older Android versions or unrelated phone frameworks would require rebuilding/decompiling the application and adapting its resources, permissions, dependencies, signing, and framework hooks for each target ROM.
