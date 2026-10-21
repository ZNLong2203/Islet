#!/bin/bash
# Builds build/Islet.app (release, ad-hoc signed).
#   VERSION=1.2.0 scripts/build-app.sh   set the version shown in Finder/About (default 0.0.0-dev)
#   scripts/build-app.sh --run          launch the app afterwards
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
ADAPTER=vendor/mediaremote-adapter
ADAPTER_COMMIT=0e82bf1

if [ ! -d "$ADAPTER" ]; then
    git clone https://github.com/ungive/mediaremote-adapter.git "$ADAPTER"
    git -C "$ADAPTER" checkout --quiet "$ADAPTER_COMMIT"
fi
if [ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
    cmake -S "$ADAPTER" -B "$ADAPTER/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$ADAPTER/build" -j 8 >/dev/null
fi

if [ ! -f Resources/AppIcon.icns ]; then
    scripts/make-icns.sh
fi

swift build -c release

APP="build/Islet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ThirdPartyLicenses" "$APP/Contents/Frameworks"
cp .build/release/Islet "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/vi.lproj "$APP/Contents/Resources/"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp "$ADAPTER/LICENSE" "$APP/Contents/Resources/ThirdPartyLicenses/mediaremote-adapter.txt"
cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - "$APP"

echo "Built $APP ($VERSION)"

if [ "${1:-}" = "--run" ]; then
    pkill -x Islet 2>/dev/null || true
    open "$APP"
fi
