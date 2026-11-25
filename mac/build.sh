#!/bin/bash
# Builds "LED Control.app" into mac/build/. Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/LED Control.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LEDControl "$APP/Contents/MacOS/LEDControl"
cp Info.plist "$APP/Contents/Info.plist"
# app icon: AppIcon.png -> AppIcon.icns (sips + iconutil ship with macOS)
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# ad-hoc signature so macOS lets the app ask for Bluetooth permission
codesign --force --deep --sign - "$APP"

echo "Built: mac/$APP"
echo "Run it with:  open \"mac/$APP\"   (or drag it into /Applications)"
