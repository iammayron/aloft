#!/bin/bash
# Build a distributable disk image. Usage: scripts/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
DMG="Aloft-$VERSION.dmg"

./build.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R Aloft.app "$STAGE/Aloft.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Aloft" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "$DMG"
shasum -a 256 "$DMG" | awk '{print $2"  sha256 "$1}'
