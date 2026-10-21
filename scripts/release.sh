#!/bin/bash
# Publishes a release: builds the app, uploads Islet.dmg (for people) and a zip (for the
# Homebrew cask) to GitHub Releases, then bumps the cask to point at it.
#   scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
TAG="v$VERSION"
ZIP="dist/Islet-$VERSION.zip"
# Unversioned so releases/latest/download/Islet.dmg always points at the newest build.
DMG="dist/Islet.dmg"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is dirty; commit first." >&2
    exit 1
fi

VERSION="$VERSION" scripts/build-app.sh
scripts/package.sh "$VERSION"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/islet.rb
git add Casks/islet.rb
git commit -m "Release $TAG"
git tag "$TAG"
git push origin HEAD "$TAG"

NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<EOF
**Download [Islet.dmg](https://github.com/ZNLong2203/Islet/releases/download/$TAG/Islet.dmg)**, drag it to Applications, then on first launch use *System Settings → Privacy & Security → Open Anyway* (Islet is open source but not notarized).

Or with Homebrew:
\`\`\`bash
brew tap znlong2203/islet https://github.com/ZNLong2203/Islet
brew install --cask znlong2203/islet/islet
\`\`\`
EOF
gh release create "$TAG" "$DMG" "$ZIP" --title "Islet $VERSION" --notes-file "$NOTES" --generate-notes

echo "Released $TAG ($SHA)"
