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
#                        `xcrun notarytool store-credentials` (default: sweepkey-notary)
#   KEYCHAIN             optional keychain holding the signing identity
#   SIGN_IDENTITY        default: "Developer ID Application"
#   SPARKLE_PUBLIC_KEY   EdDSA public key baked into the app (empty disables the updater)
#   SPARKLE_FEED_URL     appcast URL (default: the value in project.yml); must not contain the
#                        OWNER placeholder (run scripts/configure-repo.sh first)
# Credentials are never passed on the command line.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [build-number] [output-dir]}"
BUILD="${2:-$(git rev-list --count HEAD)}"
OUT="${3:-build/release}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]] || { echo "error: invalid version '$VERSION'" >&2; exit 1; }
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
PROFILE="${NOTARY_PROFILE:-sweepkey-notary}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
KC_ARGS=()
NOTARY_KC=()
if [ -n "${KEYCHAIN:-}" ]; then KC_ARGS=(--keychain "$KEYCHAIN"); NOTARY_KC=(--keychain "$KEYCHAIN"); fi

FEED_URL="${SPARKLE_FEED_URL:-$(sed -nE 's/^[[:space:]]*SPARKLE_FEED_URL:[[:space:]]*//p' project.yml | head -n 1)}"
case "$FEED_URL" in
  "") echo "error: SPARKLE_FEED_URL is empty" >&2; exit 1 ;;
  *OWNER*) echo "error: SPARKLE_FEED_URL still contains the OWNER placeholder ($FEED_URL). Run scripts/configure-repo.sh <owner>." >&2; exit 1 ;;
esac

# The CLI version comes from one place, SweepkeyKit's SweepkeyVersion.current; stamp it for this
# release and put the file back afterwards.
VERSION_FILE=Packages/SweepkeyKit/Sources/SweepkeyKit/CLISupport/Version.swift
VERSION_BACKUP=$(mktemp)
cp "$VERSION_FILE" "$VERSION_BACKUP"
trap 'cp "$VERSION_BACKUP" "$VERSION_FILE"; rm -f "$VERSION_BACKUP"' EXIT
sed -i '' -E "s/(public static let current = )\"[^\"]*\"/\1\"$VERSION\"/" "$VERSION_FILE"
grep -q "public static let current = \"$VERSION\"" "$VERSION_FILE" || { echo "error: could not stamp $VERSION_FILE" >&2; exit 1; }

sign() { codesign --force --options runtime --timestamp ${KC_ARGS[@]+"${KC_ARGS[@]}"} --sign "$IDENTITY" "$@"; }
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" ${NOTARY_KC[@]+"${NOTARY_KC[@]}"} --wait
}

rm -rf "$OUT"
mkdir -p "$OUT/dist"

# 1. CLI: build and smoke test the packaging (binary + resource bundle, via symlink).
scripts/smoke-cli.sh
CLI_BIN=$(cd Packages/SweepkeyKit && swift build -c release --product sweepkey --show-bin-path)

# 2. Archive with the release version.
xcodegen generate
xcodebuild -project Sweepkey.xcodeproj -scheme Sweepkey -configuration Release \
  -archivePath "$OUT/Sweepkey.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}" SPARKLE_FEED_URL="$FEED_URL" \
  SWEEPKEY_APP_ENTITLEMENTS=Config/Sweepkey.entitlements \
  SWEEPKEY_WIDGET_ENTITLEMENTS=Config/SweepkeyWidgets.entitlements \
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
xcodebuild -exportArchive -archivePath "$OUT/Sweepkey.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
APP="$OUT/export/Sweepkey.app"

# 4. Embed the CLI and its resource bundle (both next to each other so symlinks resolve).
ditto "$CLI_BIN/sweepkey" "$APP/Contents/Resources/sweepkey"
ditto "$CLI_BIN/SweepkeyKit_SweepkeyKit.bundle" "$APP/Contents/Resources/SweepkeyKit_SweepkeyKit.bundle"

# 5. Sign inside-out: Sparkle helpers, framework, CLI + bundle, then the app.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPK" \( -name '*.xpc' -o -name 'Updater.app' \) -print0)
  while IFS= read -r -d '' x; do sign "$x"; done < <(find "$SPK" -name Autoupdate -type f -print0)
  sign "$SPK"
fi
sign "$APP/Contents/Resources/SweepkeyKit_SweepkeyKit.bundle"
sign "$APP/Contents/Resources/sweepkey"
ENT="$OUT/app.entitlements"
if codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null && [ -s "$ENT" ]; then
  sign --entitlements "$ENT" "$APP"
else
  sign "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# 6. Notarize and staple the app, then assess it.
ditto -c -k --keepParent "$APP" "$OUT/Sweepkey-notarize.zip"
notarize "$OUT/Sweepkey-notarize.zip"
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# 7. DMG: sign, notarize, staple.
DMG="$OUT/dist/Sweepkey-$VERSION.dmg"
DMG_SIGN_IDENTITY="$IDENTITY" scripts/make-dmg.sh "$APP" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 8. Standalone CLI zip: binary + resource bundle side by side.
ZIPDIR="$OUT/cli"
mkdir -p "$ZIPDIR"
ditto "$APP/Contents/Resources/sweepkey" "$ZIPDIR/sweepkey"
ditto "$APP/Contents/Resources/SweepkeyKit_SweepkeyKit.bundle" "$ZIPDIR/SweepkeyKit_SweepkeyKit.bundle"
ditto -c -k "$ZIPDIR" "$OUT/dist/sweepkey-$VERSION-macos.zip"

echo "Artifacts in $OUT/dist"
