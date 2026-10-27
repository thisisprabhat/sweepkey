#!/bin/bash
# Smoke test of the packaged CLI: binary + resource bundle copied elsewhere and invoked through a
# symlink in a different directory (as the Homebrew `binary` stanza does).
# Usage: scripts/smoke-cli.sh
set -euo pipefail
cd "$(dirname "$0")/.."

(cd Packages/SweepkeyKit && swift build -c release --product sweepkey)
BIN=$(cd Packages/SweepkeyKit && swift build -c release --product sweepkey --show-bin-path)

WORK=$(mktemp -d)
HIDDEN="$BIN/SweepkeyKit_SweepkeyKit.bundle.hidden"
restore() {
  [ -d "$HIDDEN" ] && mv "$HIDDEN" "$BIN/SweepkeyKit_SweepkeyKit.bundle"
  rm -rf "$WORK"
}
trap restore EXIT

mkdir -p "$WORK/install" "$WORK/linkdir" "$WORK/fixture/proj/node_modules"
ditto "$BIN/sweepkey" "$WORK/install/sweepkey"
ditto "$BIN/SweepkeyKit_SweepkeyKit.bundle" "$WORK/install/SweepkeyKit_SweepkeyKit.bundle"
ln -s "$WORK/install/sweepkey" "$WORK/linkdir/sweepkey"
echo '{"name":"x"}' > "$WORK/fixture/proj/package.json"
head -c 2048 /dev/zero > "$WORK/fixture/proj/node_modules/blob"

# Hide the build-directory bundle so SwiftPM's hard-coded fallback cannot mask a lookup failure.
mv "$BIN/SweepkeyKit_SweepkeyKit.bundle" "$HIDDEN"

OUT=$("$WORK/linkdir/sweepkey" scan "$WORK/fixture" --json)
echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)>=1, d'
echo "smoke-cli OK (via symlink)"
