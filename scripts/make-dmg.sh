#!/usr/bin/env bash
# Build a Release .app and wrap it in a drag-to-Applications .dmg.
#
# Signed ad-hoc. That is enough to install and run on this machine, and on
# anyone else's after System Settings -> Privacy & Security -> Open Anyway.
# Removing that prompt needs notarization, which needs a Developer ID
# certificate, which needs the $99/year Apple Developer Program.
set -euo pipefail

APP_NAME="Notebar"
BUILD_DIR="build-release"          # separate from build/ so a Debug build can run alongside
STAGE="$BUILD_DIR/dmg-stage"
VERSION=$(grep -E '^\s+MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
DMG="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> generating project"
xcodegen generate

echo "==> building Release"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -3

APP="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

# Ad-hoc sign the bundle itself. Without this the app is unsigned rather than
# self-signed, and Gatekeeper is harsher about unsigned than about unnotarized.
echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -2

echo "==> staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "==> building dmg"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" | tail -2

rm -rf "$STAGE"
echo
echo "==> $DMG"
ls -lh "$DMG" | awk '{print "    " $5}'
echo
echo "    Install: open the dmg, drag Notebar to Applications."
echo "    On another Mac the first launch is blocked; allow it under"
echo "    System Settings -> Privacy & Security -> Open Anyway."
