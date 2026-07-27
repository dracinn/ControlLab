#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 OUTPUT_DIRECTORY" >&2
    exit 2
fi

output_directory=$1
mkdir -p "$output_directory"

if ! command -v adb >/dev/null 2>&1; then
    echo "Android platform-tools are required (adb was not found)." >&2
    exit 1
fi

adb start-server >/dev/null
device_count=$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
if [ "$device_count" -ne 1 ]; then
    echo "Connect and authorize exactly one Android device; found $device_count." >&2
    adb devices -l >&2
    exit 1
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
bugreport="$output_directory/flydigi-bugreport-$timestamp.zip"

echo "Collecting an Android bug report. This can contain private device data."
echo "Keep the ZIP local and share only the extracted Bluetooth capture."
adb bugreport "$bugreport"
echo "Saved $bugreport"
echo "Run scripts/analyze-android-hci.sh on this ZIP to extract Bluetooth traffic."
