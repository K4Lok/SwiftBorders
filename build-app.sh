#!/usr/bin/env bash
# Builds SwiftBorder.app: compiles release, assembles the bundle, and code-signs
# it for direct distribution (Developer ID + Hardened Runtime).
#
# Usage:
#   ./build-app.sh                 # autodetect "Developer ID Application" cert
#   CODESIGN_IDENTITY="..." ./build-app.sh   # force a specific identity
#
# After this, run ./notarize.sh to notarize & staple for distribution.
set -euo pipefail

APP_NAME="SwiftBorder"
BUNDLE_ID="com.swiftborder.app"
VERSION="1.0.0"
BUILD="1"
MIN_OS="13.0"
COPYRIGHT="© 2026 Ka Lok Sam"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/Packaging"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
RELEASE_BIN="$ROOT/.build/release/$APP_NAME"

# ── 1. Compile release binary ───────────────────────────────────────────────
echo "▸ Building release binary…"
swift build -c release --product "$APP_NAME"

# ── 2. Ensure the icon exists ───────────────────────────────────────────────
if [ ! -f "$PKG/AppIcon.icns" ]; then
  echo "▸ Generating app icon…"
  ( cd "$PKG"
    swift make-icon.swift
    rm -rf AppIcon.iconset && mkdir AppIcon.iconset
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" \
                "64:icon_32x32@2x" "128:icon_128x128" "256:icon_128x128@2x" \
                "256:icon_256x256" "512:icon_256x256@2x" "512:icon_512x512" \
                "1024:icon_512x512@2x"; do
      sz="${spec%%:*}"; name="${spec##*:}"
      sips -z "$sz" "$sz" icon-1024.png --out "AppIcon.iconset/$name.png" >/dev/null
    done
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset )
fi

# ── 3. Assemble the .app bundle ─────────────────────────────────────────────
echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$RELEASE_BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$PKG/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_OS</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key> <string>$COPYRIGHT</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# ── 4. Code-sign (Hardened Runtime) ─────────────────────────────────────────
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(.*)".*/\1/' || true)"
fi

if [ -z "$IDENTITY" ]; then
  echo "⚠️  No 'Developer ID Application' certificate found."
  echo "    Signing ad-hoc so the app runs locally, but it CANNOT be notarized."
  echo "    Create the cert in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates,"
  echo "    then re-run this script."
  codesign --force --sign - "$APP"
else
  echo "▸ Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

echo ""
echo "✅ Built: $APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|Identifier|Runtime" || true
echo ""
echo "Next: ./notarize.sh   (requires a notarytool credential profile)"
