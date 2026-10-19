#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) release binary, wraps it in
# build/Lime.app (ad-hoc signed) and zips it as build/Lime.zip for releases.
set -euo pipefail
cd "$(dirname "$0")/.."

BINARIES=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx13.0"
  swift build -c release --triple "$triple"
  BINARIES+=("$(swift build -c release --triple "$triple" --show-bin-path)/Lime")
done

APP=build/Lime.app
rm -rf "$APP" build/Lime.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Lime"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" build/Lime.zip

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Lime")) and build/Lime.zip"
echo "Install: cp -R $APP /Applications/"
