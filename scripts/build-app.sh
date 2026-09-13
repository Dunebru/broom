#!/usr/bin/env bash
# Builds dist/Broom.app (+ zip) from the SwiftPM package. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E "error|warning: unre|Build complete" || true
APP="dist/Broom.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Broom "$APP/Contents/MacOS/Broom"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
# Ad-hoc signature with a stable identifier so macOS remembers Full Disk Access across rebuilds.
codesign --force --sign - --identifier com.dunebru.broom --options runtime --entitlements packaging/Broom.entitlements "$APP" 2>/dev/null \
  || codesign --force --sign - --identifier com.dunebru.broom "$APP"
rm -f dist/Broom.zip
ditto -c -k --keepParent "$APP" dist/Broom.zip
echo "→ $APP  ($(du -sh "$APP" | cut -f1))"
