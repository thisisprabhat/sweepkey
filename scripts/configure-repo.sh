#!/bin/bash
# Replace the OWNER placeholder with your GitHub user or organisation.
# Usage: scripts/configure-repo.sh <owner>
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <github-owner>" >&2; exit 1; }
OWNER="$1"
case "$OWNER" in *[!A-Za-z0-9-]*|"") echo "error: invalid owner" >&2; exit 1;; esac
cd "$(dirname "$0")/.."
git ls-files -z | grep -zv '^scripts/configure-repo.sh$' | xargs -0 grep -lZ 'OWNER' 2>/dev/null \
  | xargs -0 sed -i '' "s#github.com/OWNER/#github.com/$OWNER/#g; s#homebrew-tap/OWNER#homebrew-tap/$OWNER#g" || true
echo "Replaced OWNER with $OWNER"
