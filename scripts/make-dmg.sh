#!/bin/bash
# Build a DMG containing Cleaner.app and an /Applications symlink.
#
# Usage: scripts/make-dmg.sh [path/to/Cleaner.app] [output.dmg]
#
# With no app path, builds a Release app locally (ad-hoc signed) into .build/xcode.
# Env: DMG_SIGN_IDENTITY  codesign identity for the DMG itself (optional; skipped if unset)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
OUT="${2:-}"

if [ -z "$APP" ]; then
  xcodegen generate
  xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release \
    -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build >/dev/null
  APP=".build/xcode/Build/Products/Release/Cleaner.app"
fi
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="${OUT:-Cleaner-$VERSION.dmg}"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Cleaner.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Cleaner $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null

if [ -n "${DMG_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "$OUT"
