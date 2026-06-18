#!/usr/bin/env bash
# Packages dist/SwiftBorder.app into a drag-to-Applications DMG.
# Run AFTER ./build-app.sh (and ideally ./notarize.sh, so the app inside is
# already stapled). The DMG itself should then be notarized+stapled too —
# notarize.sh does that automatically if the DMG exists.
set -euo pipefail

APP_NAME="SwiftBorder"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"
STAGE="$ROOT/dist/.dmg-stage"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build-app.sh first."; exit 1; }

echo "▸ Staging DMG contents…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "▸ Building $APP_NAME.dmg…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "✅ Created $DMG"