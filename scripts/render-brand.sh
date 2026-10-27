#!/bin/bash
# Re-render the committed raster brand assets from their SVG sources in Branding/.
# Only needed after editing an SVG; builds and releases use the committed outputs.
#
# Usage: scripts/render-brand.sh
# Needs Google Chrome (headless) for SVG rendering, plus tiffutil (ships with macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "error: Chrome not found at $CHROME (set CHROME=...)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# render <svg> <width> <height> <scale> <out.png>
render() {
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size="$2,$3" --force-device-scale-factor="$4" --screenshot="$5" "file://$PWD/$1" >/dev/null 2>&1
  [ -s "$5" ] || { echo "error: failed to render $1" >&2; exit 1; }
}

# DMG window background: 1x and 2x combined into one HiDPI TIFF that Finder picks from.
render Branding/dmg-background.svg 660 400 1 "$WORK/bg.png"
render Branding/dmg-background.svg 660 400 2 "$WORK/bg@2x.png"
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out Branding/dmg-background.tiff >/dev/null
echo "Branding/dmg-background.tiff"
