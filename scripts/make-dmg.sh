#!/bin/bash
# Build the Sweepkey installer DMG: a branded window (Branding/dmg-background.tiff) with the app
# on the left and an /Applications link on the right. The Finder layout is written by dmgbuild,
# which needs no Finder automation, so this works headless and in CI.
#
# Usage: scripts/make-dmg.sh [path/to/Sweepkey.app] [output.dmg]
#
# With no app path, builds a Release app locally (ad-hoc signed) into .build/xcode.
# Env: DMG_SIGN_IDENTITY  codesign identity for the DMG itself (optional; skipped if unset)
set -euo pipefail
APP="${1:-}"
OUT="${2:-}"
# Resolve caller-relative paths before changing directory.
[ -z "$APP" ] || APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
[ -z "$OUT" ] || OUT="$(mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
cd "$(dirname "$0")/.."

if [ -z "$APP" ]; then
  # Ad-hoc signatures carry no Team ID, so with the hardened runtime on, library validation
  # refuses to load the embedded Sparkle.framework and the app dies at launch. Notarized
  # releases (scripts/release.sh) sign everything with one Developer ID and keep the runtime.
  xcodegen generate
  xcodebuild -project Sweepkey.xcodeproj -scheme Sweepkey -configuration Release \
    -derivedDataPath .build/xcode -quiet CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO build
  APP=".build/xcode/Build/Products/Release/Sweepkey.app"
  APP="$PWD/$APP"
fi
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="${OUT:-$PWD/Sweepkey-$VERSION.dmg}"

# dmgbuild is pinned and kept in a private venv under .build (system python3, no global installs).
VENV=.build/dmg-venv
DMGBUILD_VERSION=1.6.5
if ! "$VENV/bin/dmgbuild" --help >/dev/null 2>&1 \
  || [ "$("$VENV/bin/python3" -c 'import importlib.metadata as m; print(m.version("dmgbuild"))')" != "$DMGBUILD_VERSION" ]; then
  rm -rf "$VENV"
  /usr/bin/python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" "Sweepkey $VERSION" "$OUT" >/dev/null

if [ -n "${DMG_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "$OUT"
