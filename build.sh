#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
task_build_dir="${1:-build}"
mkdir -p "$task_build_dir"
task_build_dir="$(cd "$task_build_dir" && pwd)"
task_app="$task_build_dir/OLED Shade.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"

swiftc -O Sources/IdlePolicy.swift Tests/main.swift -o "$task_build_dir/IdlePolicyTests"
"$task_build_dir/IdlePolicyTests"

for task_arch in arm64 x86_64; do
    swiftc -O -whole-module-optimization -target "$task_arch-apple-macos13.0" \
        Sources/IdlePolicy.swift Sources/main.swift \
        -framework AppKit -framework CoreGraphics \
        -o "$task_build_dir/OLEDShade-$task_arch"
done
lipo -create "$task_build_dir/OLEDShade-arm64" "$task_build_dir/OLEDShade-x86_64" \
    -output "$task_app/Contents/MacOS/OLEDShade"
cp Info.plist "$task_app/Contents/Info.plist"
swift make-icon.swift "$task_build_dir/AppIcon.iconset"
iconutil -c icns "$task_build_dir/AppIcon.iconset" -o "$task_app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$task_app"
codesign --verify --strict "$task_app"
printf 'Built %s\n' "$task_app"
