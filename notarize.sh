#!/usr/bin/env bash
# Notarizes and staples SwiftBorder.app, then produces a distributable zip.
#
# ONE-TIME SETUP — store your notarization credentials in the keychain:
#
#   xcrun notarytool store-credentials "SwiftBorder-Notary" \
#       --apple-id "you@example.com" \
#       --team-id  "YOURTEAMID" \
#       --password "app-specific-password"
#
#   • Apple ID  = the email on your Developer account
#   • Team ID   = found at https://developer.apple.com/account (top right)
#   • password  = an app-specific password from https://account.apple.com
#                 (Sign-In & Security ▸ App-Specific Passwords) — NOT your
#                 normal Apple ID password.
#
# Then just run:  ./notarize.sh
set -euo pipefail

APP_NAME="SwiftBorder"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
ZIP="$ROOT/dist/$APP_NAME.zip"
PROFILE="${NOTARY_PROFILE:-SwiftBorder-Notary}"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build-app.sh first."; exit 1; }

# Confirm it's Developer-ID signed (ad-hoc can't be notarized).
# NB: capture first — piping straight into `grep -q` makes codesign die with
# SIGPIPE, which `set -o pipefail` would then misread as "check failed".
SIG_INFO="$(codesign -dvv "$APP" 2>&1)"
if ! grep -q "Developer ID Application" <<<"$SIG_INFO"; then
  echo "✗ $APP is not signed with a Developer ID Application certificate."
  echo "  Create the cert and re-run ./build-app.sh, then notarize."
  exit 1
fi

echo "▸ Zipping for submission…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Re-zipping the stapled app for distribution…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Build a DMG from the stapled app, then notarize + staple the DMG itself.
DMG="$ROOT/dist/$APP_NAME.dmg"
echo "▸ Building DMG…"
"$ROOT/make-dmg.sh"
echo "▸ Notarizing the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "✅ Notarized & stapled."
echo "   App: $APP"
echo "   Distributables: $ZIP"
echo "                   $DMG"
echo "   Verify on a clean machine: spctl -a -vvv \"$APP\""
