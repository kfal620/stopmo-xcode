#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-StopmoXcodeGUI}"
BUNDLE_ID="${BUNDLE_ID:-com.stopmo.xcode.gui}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST_DIR="${DIST_DIR:-${GUI_ROOT}/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

INFO_PLIST_TEMPLATE="${GUI_ROOT}/packaging/Info.plist"
ENTITLEMENTS_PLIST="${GUI_ROOT}/packaging/entitlements.plist"

if [[ ! -f "${INFO_PLIST_TEMPLATE}" ]]; then
  echo "missing Info.plist template: ${INFO_PLIST_TEMPLATE}" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"

echo "Building ${APP_NAME} (release)..."
swift build -c release --product "${APP_NAME}" --package-path "${GUI_ROOT}"
BIN_DIR="$(swift build -c release --product "${APP_NAME}" --show-bin-path --package-path "${GUI_ROOT}")"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "release binary missing: ${BIN_PATH}" >&2
  exit 1
fi

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

echo "Creating app bundle: ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${INFO_PLIST_TEMPLATE}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_BUNDLE}/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "Signing bundle with identity: ${SIGN_IDENTITY}"
  codesign \
    --deep \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "${ENTITLEMENTS_PLIST}" \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
  spctl --assess --type execute --verbose=2 "${APP_BUNDLE}" || true
else
  echo "SIGN_IDENTITY not set; skipping codesign"
fi

echo "Packaging zip: ${ZIP_PATH}"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "Release artifact created:"
echo "  App: ${APP_BUNDLE}"
echo "  Zip: ${ZIP_PATH}"
