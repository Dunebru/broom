#!/usr/bin/env bash
# Shared release signing for the dunebru apps.
#   usage: notarize-common.sh <path/to/App.app> <bundle-id> [entitlements.plist]
# Signs with Developer ID (hardened runtime, timestamp), notarizes with notarytool, staples,
# and writes <App>.zip next to the .app. Uses the App Store Connect key in ~/.appstoreconnect.
set -euo pipefail
APP="$1"; BUNDLE_ID="$2"; ENT="${3:-}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_Z2GF27X5FJ.p8" --key-id Z2GF27X5FJ --issuer 1797278a-1e6f-4e5d-9332-8419e99552d3)
NAME="$(basename "$APP" .app)"
DIST="$(dirname "$APP")"

# Sign nested code first: frameworks, bundles, helper executables, Metal libraries.
find "$APP/Contents" -type f \( -perm -u+x -o -name "*.dylib" -o -name "*.metallib" \) -not -path "*/MacOS/$NAME" | while read -r f; do
  if file "$f" | grep -qE "Mach-O"; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f" >/dev/null 2>&1 || codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "${HELPER_ENTITLEMENTS:-/dev/null}" "$f"
  fi
done
find "$APP/Contents" -type d \( -name "*.bundle" -o -name "*.framework" -o -name "*.mlmodelc" \) | while read -r b; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$b" >/dev/null 2>&1 || true
done

if [ -n "$ENT" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier "$BUNDLE_ID" --entitlements "$ENT" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --deep --strict "$APP"

ZIP="$DIST/$NAME.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "→ notarizing $NAME"
xcrun notarytool submit "$ZIP" "${NOTARY[@]}" --wait 2>&1 | grep -E "status|id:" | tail -3
xcrun stapler staple "$APP" >/dev/null
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute -v "$APP" 2>&1 | tail -1
echo "→ $ZIP ($(du -h "$ZIP" | cut -f1))"
