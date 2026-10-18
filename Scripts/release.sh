#!/bin/bash
# One command per release: archive → export (Developer ID) → notarize → staple → zip → private GitHub release.
# One-time setup (see README.md): Developer ID Application cert in Xcode, `notarytool store-credentials ydnt`.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
OUT=build/release
APP="$OUT/YouDontNeedThat.app"
ZIP="$OUT/YouDontNeedThat-$VERSION.zip"
rm -rf "$OUT"; mkdir -p "$OUT"

xcodegen generate
xcodebuild archive -project YouDontNeedThat.xcodeproj -scheme YouDontNeedThat -configuration Release \
  -archivePath "$OUT/YouDontNeedThat.xcarchive" -destination 'generic/platform=macOS' | xcbeautify 2>/dev/null || true
[ -d "$OUT/YouDontNeedThat.xcarchive" ] || { echo "archive failed"; exit 1; }
xcodebuild -exportArchive -archivePath "$OUT/YouDontNeedThat.xcarchive" -exportOptionsPlist ExportOptions.plist -exportPath "$OUT"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile ydnt --wait
xcrun stapler staple "$APP"
rm "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip so the staple ships inside
spctl -a -vv "$APP"

gh release create "v$VERSION" "$ZIP" --title "v$VERSION" --notes "Unzip, drag to /Applications, open."
echo "Released v$VERSION"
