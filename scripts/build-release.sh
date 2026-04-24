#!/usr/bin/env bash
# Build an unsigned (ad-hoc signed) .app and wrap it in a DMG for dev preview.
# Requirements: Xcode 15+, xcodegen, create-dmg (all available via brew).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/ZaDarkHelper"
BUILD_DIR="$ROOT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
ARCHIVE_PATH="$BUILD_DIR/ZaDarkHelper.xcarchive"

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Generating Xcode project via xcodegen"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not installed. Run: brew install xcodegen" >&2
  exit 1
fi
(cd "$APP_DIR" && xcodegen generate)

echo "==> Archiving"
xcodebuild \
  -project "$APP_DIR/ZaDarkHelper.xcodeproj" \
  -scheme ZaDarkHelper \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  archive

echo "==> Exporting .app"
mkdir -p "$EXPORT_DIR"
# We cannot use exportArchive without a provisioning profile for signed builds,
# so we copy the .app directly out of the archive.
cp -R "$ARCHIVE_PATH/Products/Applications/ZaDarkHelper.app" "$EXPORT_DIR/"

echo "==> Ad-hoc signing (prevents 'damaged' error on first open)"
codesign --deep --force --sign - "$EXPORT_DIR/ZaDarkHelper.app"

VERSION="$(defaults read "$EXPORT_DIR/ZaDarkHelper.app/Contents/Info" CFBundleShortVersionString)"
DMG_PATH="$BUILD_DIR/ZaDarkHelper-${VERSION}.dmg"

echo "==> Building DMG: $DMG_PATH"
"$ROOT_DIR/scripts/make-dmg.sh" "$EXPORT_DIR/ZaDarkHelper.app" "$DMG_PATH"

echo "==> Done: $DMG_PATH"
