#!/system/bin/sh
set -eu

sdk="$(getprop ro.build.version.sdk)"
abis="$(getprop ro.product.cpu.abilist)"
settings_path="$(pm path com.android.settings 2>/dev/null || true)"
service_path="$(pm path com.google.android.settings.intelligence 2>/dev/null || true)"

echo "Android SDK: ${sdk:-unknown}"
echo "ABIs: ${abis:-unknown}"
echo "Settings package: ${settings_path:-not installed}"
echo "Settings Intelligence: ${service_path:-not installed}"

if [ -z "${sdk}" ] || [ "${sdk}" -lt 37 ]; then
    echo "FAIL: SettingsGoogle.apk requires Android SDK 37 or newer." >&2
    exit 1
fi

case ",${abis}," in
    *,arm64-v8a,*) ;;
    *)
        echo "FAIL: base.apk contains ARM64 native libraries and this device does not advertise arm64-v8a." >&2
        exit 1
        ;;
esac

if [ -z "${settings_path}" ]; then
    echo "WARN: com.android.settings is not installed; this bundle is not a standalone Settings app."
fi

echo "PASS: basic SDK and ABI checks passed. Framework, signer, resource, and privileged-permission compatibility still need target-ROM validation."
