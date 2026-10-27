#!/bin/bash
# Local helper used by the release workflow: archive, export (Developer ID), notarize, staple, DMG.
# Requires the signing identity in the keychain and notarytool credentials in env:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD, and optionally SPARKLE_PUBLIC_KEY.
# Usage: scripts/release.sh <output-dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: release.sh <output-dir>}"
mkdir -p "$OUT"
: "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"

xcodegen generate
xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release \
  -archivePath "$OUT/Cleaner.xcarchive" \
  SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive

# Embed the signed CLI so the Homebrew cask can link it from the app bundle.
(cd Packages/CleanerKit && swift build -c release --product cleaner)
CLI="$(cd Packages/CleanerKit && swift build -c release --product cleaner --show-bin-path)/cleaner"
APP_IN_ARCHIVE="$OUT/Cleaner.xcarchive/Products/Applications/Cleaner.app"
cp "$CLI" "$APP_IN_ARCHIVE/Contents/Resources/cleaner"
codesign --force --options runtime --timestamp --sign "Developer ID Application" \
  "$APP_IN_ARCHIVE/Contents/Resources/cleaner"
codesign --force --options runtime --timestamp --sign "Developer ID Application" \
  --preserve-metadata=entitlements "$APP_IN_ARCHIVE"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$APPLE_TEAM_ID</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Cleaner.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"

ditto -c -k --keepParent "$OUT/export/Cleaner.app" "$OUT/Cleaner-notarize.zip"
xcrun notarytool submit "$OUT/Cleaner-notarize.zip" --wait \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
xcrun stapler staple "$OUT/export/Cleaner.app"
spctl -a -vv "$OUT/export/Cleaner.app"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$OUT/export/Cleaner.app/Contents/Info.plist")
scripts/make-dmg.sh "$OUT/export/Cleaner.app" "$OUT/Cleaner-$VERSION.dmg"
xcrun notarytool submit "$OUT/Cleaner-$VERSION.dmg" --wait \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
xcrun stapler staple "$OUT/Cleaner-$VERSION.dmg"
echo "$OUT/Cleaner-$VERSION.dmg"
