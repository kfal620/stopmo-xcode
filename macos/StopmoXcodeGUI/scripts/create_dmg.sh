#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-StopmoXcodeGUI}"
VERSION="${VERSION:-0.2.0}"
DIST_DIR="${DIST_DIR:-${GUI_ROOT}/dist}"
APP_BUNDLE="${APP_BUNDLE:-${DIST_DIR}/${APP_NAME}.app}"
DMG_PATH="${DMG_PATH:-${DIST_DIR}/${APP_NAME}-${VERSION}.dmg}"
VOL_NAME="${VOL_NAME:-${APP_NAME}}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
STAGING_DIR="$DIST_DIR/.dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "created dmg: $DMG_PATH"
