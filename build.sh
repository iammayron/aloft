#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Aloft.app"
IDENTITY="${ALOFT_IDENTITY:-7CD64AA721195F85C1B7AF29D0FCFEC94A576EE5}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Aloft</string>
  <key>CFBundleDisplayName</key><string>Aloft</string>
  <key>CFBundleIdentifier</key><string>dev.mayron.aloft</string>
  <key>CFBundleExecutable</key><string>Aloft</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.3</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Aloft</string>
</dict>
</plist>
PLIST

swiftc -O -parse-as-library \
  -target arm64-apple-macos26.0 \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Aloft" \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework AVFoundation -framework Carbon

mkdir -p "$APP/Contents/Resources"
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --minimum-deployment-target 26.0 \
  --output-partial-info-plist /tmp/aloft-icon.plist > /dev/null

codesign --force --options runtime --sign "$IDENTITY" "$APP"

# Every build deletes and recreates the bundle, so anything holding a reference to the
# old one (System Settings' privacy rows, the Dock) loses the icon until it is
# re-registered.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP"

echo "built $(pwd)/$APP"
