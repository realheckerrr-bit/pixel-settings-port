# Tools

`inspect-apk.ps1` reads the binary Android manifest without modifying either APK.

`check-device.ps1` and `check-device.sh` perform only basic SDK, ABI, and package-presence checks. They intentionally do not replace `/system`, mount overlays, disable the stock Settings package, or flash a Magisk module. Those operations are target-ROM-specific and can soft-brick a device when the platform certificate or framework is incompatible.
