#!/bin/bash
# The single release pipeline: CLI build + smoke test, archive, export (Developer ID), embed CLI,
# inside-out signing, notarize, staple, verify, DMG, CLI zip. Used by CI and runnable locally.
#
# Usage: scripts/release.sh <version> [build-number] [output-dir]
#   version       e.g. 1.2.3 (no leading "v")
#   build-number  default: git rev-list --count HEAD
#   output-dir    default: build/release   (artifacts land in <output-dir>/dist)
#
# Environment:
#   APPLE_TEAM_ID        required
#   NOTARY_PROFILE       notarytool keychain profile, created beforehand with
#                        `xcrun notarytool store-credentials` (default: cleaner-notary)
#   KEYCHAIN             optional keychain holding the signing identity
#   SIGN_IDENTITY        default: "Developer ID Application"
#   SPARKLE_PUBLIC_KEY   EdDSA public key baked into the app (empty disables the updater)
# Credentials are never passed on the command line.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [build-number] [output-dir]}"
BUILD="${2:-$(git rev-list --count HEAD)}"
OUT="${3:-build/release}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
PROFILE="${NOTARY_PROFILE:-cleaner-notary}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
KC_ARGS=()
NOTARY_KC=()
if [ -n "${KEYCHAIN:-}" ]; then KC_ARGS=(--keychain "$KEYCHAIN"); NOTARY_KC=(--keychain "$KEYCHAIN"); fi

sign() { codesign --force --options runtime --timestamp "${KC_ARGS[@]}" --sign "$IDENTITY" "$@"; }
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" "${NOTARY_KC[@]}" --wait
}

rm -rf "$OUT"
mkdir -p "$OUT/dist"

# 1. CLI: build and smoke test the packaging (binary + resource bundle, via symlink).
scripts/smoke-cli.sh
CLI_BIN=$(cd Packages/CleanerKit && swift build -c release --product cleaner --show-bin-path)

# 2. Archive with the release version.
xcodegen generate
xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release \
  -archivePath "$OUT/Cleaner.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp ${KEYCHAIN:+--keychain $KEYCHAIN}" \
  archive

# 3. Export with Developer ID.
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$APPLE_TEAM_ID</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>$IDENTITY</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Cleaner.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
APP="$OUT/export/Cleaner.app"

# 4. Embed the CLI and its resource bundle (both next to each other so symlinks resolve).
ditto "$CLI_BIN/cleaner" "$APP/Contents/Resources/cleaner"
ditto "$CLI_BIN/CleanerKit_CleanerKit.bundle" "$APP/Contents/Resources/CleanerKit_CleanerKit.bundle"

# 5. Sign inside-out: Sparkle helpers, framework, CLI + bundle, then the app.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPK" \( -name '*.xpc' -o -name 'Updater.app' \) -print0)
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPK" -name Autoupdate -type f -print0)
  sign "$SPK"
fi
sign "$APP/Contents/Resources/CleanerKit_CleanerKit.bundle"
sign "$APP/Contents/Resources/cleaner"
ENT="$OUT/app.entitlements"
if codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null && [ -s "$ENT" ]; then
  sign --entitlements "$ENT" "$APP"
else
  sign "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# 6. Notarize and staple the app, then assess it.
ditto -c -k --keepParent "$APP" "$OUT/Cleaner-notarize.zip"
notarize "$OUT/Cleaner-notarize.zip"
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# 7. DMG: sign, notarize, staple.
DMG="$OUT/dist/Cleaner-$VERSION.dmg"
DMG_SIGN_IDENTITY="$IDENTITY" scripts/make-dmg.sh "$APP" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 8. Standalone CLI zip: binary + resource bundle side by side.
ZIPDIR="$OUT/cli"
mkdir -p "$ZIPDIR"
ditto "$APP/Contents/Resources/cleaner" "$ZIPDIR/cleaner"
ditto "$APP/Contents/Resources/CleanerKit_CleanerKit.bundle" "$ZIPDIR/CleanerKit_CleanerKit.bundle"
ditto -c -k "$ZIPDIR" "$OUT/dist/cleaner-$VERSION-macos.zip"

echo "Artifacts in $OUT/dist"
