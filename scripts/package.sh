#!/bin/bash
# Packages build/Islet.app into dist/Islet.dmg (drag-to-Applications) and dist/Islet-<version>.zip.
#   scripts/package.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/package.sh <version>}"
mkdir -p dist
rm -f "dist/Islet-$VERSION.zip" dist/Islet.dmg

ditto -c -k --sequesterRsrc --keepParent build/Islet.app "dist/Islet-$VERSION.zip"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Islet.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Islet" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov dist/Islet.dmg 2> >(grep -v deprecated >&2) >/dev/null

ls -lh dist
