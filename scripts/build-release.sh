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

# Prefer the stable self-signed identity (set up by scripts/create-dev-cert.sh)
# so TCC grants (App Management, etc.) persist across versions on this machine.
# Match by SHA1 to disambiguate duplicate imports (login keychain sometimes holds
# two copies after multiple `security import` runs). Fall back to ad-hoc "-"
# when the identity is absent (e.g. fresh CI box).
IDENTITY_SHA=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/"ZaDarkHelperDev"$/ {print $2; exit}')
if [ -n "$IDENTITY_SHA" ]; then
  SIGN_IDENTITY="$IDENTITY_SHA"
  echo "==> Signing identity: ZaDarkHelperDev ($IDENTITY_SHA) — TCC-stable"
else
  SIGN_IDENTITY="-"
  echo "==> Signing identity: ad-hoc (run scripts/create-dev-cert.sh for TCC stability)"
fi

echo "==> Archiving"
xcodebuild \
  -project "$APP_DIR/ZaDarkHelper.xcodeproj" \
  -scheme ZaDarkHelper \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  archive

echo "==> Exporting .app"
mkdir -p "$EXPORT_DIR"
# Copy the .app directly out of the archive; exportArchive needs a profile we don't have.
cp -R "$ARCHIVE_PATH/Products/Applications/ZaDarkHelper.app" "$EXPORT_DIR/"

echo "==> Re-signing with $SIGN_IDENTITY (keeps signature consistent across versions)"
codesign --deep --force --sign "$SIGN_IDENTITY" "$EXPORT_DIR/ZaDarkHelper.app"

VERSION="$(defaults read "$EXPORT_DIR/ZaDarkHelper.app/Contents/Info" CFBundleShortVersionString)"
DMG_PATH="$BUILD_DIR/ZaDarkHelper-${VERSION}.dmg"

echo "==> Building DMG: $DMG_PATH"
"$ROOT_DIR/scripts/make-dmg.sh" "$EXPORT_DIR/ZaDarkHelper.app" "$DMG_PATH"

echo "==> Done: $DMG_PATH"
