#!/usr/bin/env bash
# Wrap a .app bundle in a DMG with an Applications symlink.
# Usage: make-dmg.sh <path/to/App.app> <path/to/output.dmg>
set -euo pipefail

APP_PATH="${1:?path to .app required}"
DMG_PATH="${2:?output dmg path required}"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not installed. Run: brew install create-dmg" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
VOLNAME="${APP_NAME%.app}"

# create-dmg fails if the output file already exists.
rm -f "$DMG_PATH"

create-dmg \
  --volname "$VOLNAME" \
  --window-pos 200 120 \
  --window-size 540 340 \
  --icon-size 96 \
  --icon "$APP_NAME" 130 160 \
  --app-drop-link 410 160 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"
