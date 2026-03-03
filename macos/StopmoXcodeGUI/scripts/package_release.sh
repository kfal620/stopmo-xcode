#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GUI_ROOT}/../.." && pwd)"

APP_NAME="${APP_NAME:-FrameRelay}"
BUNDLE_ID="${BUNDLE_ID:-com.framerelay.gui}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST_DIR="${DIST_DIR:-${GUI_ROOT}/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"
ARCHES="${ARCHES:-arm64 x86_64}"
XCODE_SCHEME="${XCODE_SCHEME:-StopmoXcodeGUI-Release}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

INFO_PLIST_TEMPLATE="${GUI_ROOT}/packaging/Info.plist"
ENTITLEMENTS_PLIST="${GUI_ROOT}/packaging/entitlements.plist"
XCODEPROJ_PATH="${GUI_ROOT}/StopmoXcodeGUI.xcodeproj"
BACKEND_RUNTIME_DIR="${DIST_DIR}/backend-runtime"

require_tool() {
  local tool_name="$1"
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "required tool not found: $tool_name" >&2
    exit 1
  fi
}

verify_sign_identity() {
  local identity="$1"
  local matches
  matches="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$identity" || true)"
  if [[ -z "$matches" ]]; then
    echo "SIGN_IDENTITY not found in login keychain codesigning identities: $identity" >&2
    echo "Run: security find-identity -v -p codesigning" >&2
    exit 1
  fi
}

verify_notary_profile() {
  local profile="$1"
  if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "NOTARY_PROFILE not found or not accessible: $profile" >&2
    echo "Create it with: xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific-password>" >&2
    exit 1
  fi
}

if [[ ! -d "$XCODEPROJ_PATH" ]]; then
  echo "xcodeproj not found: $XCODEPROJ_PATH" >&2
  exit 1
fi
if [[ ! -f "$INFO_PLIST_TEMPLATE" ]]; then
  echo "missing Info.plist template: $INFO_PLIST_TEMPLATE" >&2
  exit 1
fi
if [[ ! -f "$ENTITLEMENTS_PLIST" ]]; then
  echo "missing entitlements file: $ENTITLEMENTS_PLIST" >&2
  exit 1
fi
if [[ "$ALLOW_UNSIGNED" != "1" && -z "$SIGN_IDENTITY" ]]; then
  echo "SIGN_IDENTITY is required for release packaging (set ALLOW_UNSIGNED=1 only for local smoke builds)." >&2
  exit 1
fi
if [[ "$NOTARIZE" == "1" && -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required when NOTARIZE=1." >&2
  exit 1
fi

require_tool xcodebuild
require_tool lipo
require_tool codesign
require_tool hdiutil
require_tool xcrun
if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  verify_sign_identity "$SIGN_IDENTITY"
fi
if [[ "$NOTARIZE" == "1" ]]; then
  verify_notary_profile "$NOTARY_PROFILE"
fi

mkdir -p "$DIST_DIR"

DERIVED_DATA="${DIST_DIR}/.derivedData"
rm -rf "$DERIVED_DATA"

build_args=(
  -project "$XCODEPROJ_PATH"
  -scheme "$XCODE_SCHEME"
  -configuration Release
  -derivedDataPath "$DERIVED_DATA"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  build
)
for arch in $ARCHES; do
  build_args=(-arch "$arch" "${build_args[@]}")
done

echo "Building universal app via xcodebuild (${ARCHES})..."
xcodebuild "${build_args[@]}"

BUILT_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "release app missing: $BUILT_APP" >&2
  exit 1
fi

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
MANIFEST_PATH="${DIST_DIR}/manifest.json"

rm -rf "$APP_BUNDLE"
cp -R "$BUILT_APP" "$APP_BUNDLE"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP_BUNDLE/Contents/Info.plist"

MAIN_BIN="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ ! -x "$MAIN_BIN" ]]; then
  echo "main executable missing: $MAIN_BIN" >&2
  exit 1
fi
for arch in $ARCHES; do
  lipo "$MAIN_BIN" -verify_arch "$arch"
done

echo "Building backend runtimes (${ARCHES})..."
OUT_DIR="$BACKEND_RUNTIME_DIR" ARCHES="$ARCHES" "$SCRIPT_DIR/build_backend_runtime.sh"

BACKEND_DEST="$APP_BUNDLE/Contents/Resources/backend"
rm -rf "$BACKEND_DEST"
mkdir -p "$BACKEND_DEST/runtimes" "$BACKEND_DEST/defaults"

for arch in $ARCHES; do
  if [[ ! -d "$BACKEND_RUNTIME_DIR/$arch" ]]; then
    echo "missing backend runtime for architecture: $arch" >&2
    exit 1
  fi
  cp -R "$BACKEND_RUNTIME_DIR/$arch" "$BACKEND_DEST/runtimes/$arch"
done

cp "$SCRIPT_DIR/backend_launch_bridge.sh" "$BACKEND_DEST/launch_bridge.sh"
chmod +x "$BACKEND_DEST/launch_bridge.sh"

if [[ -f "$REPO_ROOT/config/sample.yaml" ]]; then
  cp "$REPO_ROOT/config/sample.yaml" "$BACKEND_DEST/defaults/sample.yaml"
fi
if [[ -f "$BACKEND_RUNTIME_DIR/manifest.json" ]]; then
  cp "$BACKEND_RUNTIME_DIR/manifest.json" "$MANIFEST_PATH"
fi

sign_one() {
  local target="$1"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$target"
}

if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  echo "Signing nested runtime payloads with identity: $SIGN_IDENTITY"
  while IFS= read -r target; do
    sign_one "$target"
  done < <(find "$BACKEND_DEST" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) | sort)

  sign_one "$MAIN_BIN"
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PLIST" \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

  codesign --verify --strict --verbose=2 "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
else
  echo "ALLOW_UNSIGNED=1 set; skipping codesign."
fi

APP_BUNDLE="$APP_BUNDLE" APP_NAME="$APP_NAME" VERSION="$VERSION" DIST_DIR="$DIST_DIR" DMG_PATH="$DMG_PATH" "$SCRIPT_DIR/create_dmg.sh"

if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  sign_one "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  NOTARY_PROFILE="$NOTARY_PROFILE" "$SCRIPT_DIR/notarize_release.sh" "$DMG_PATH" "$APP_BUNDLE"
fi

echo "Release artifacts created:"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
if [[ -f "$MANIFEST_PATH" ]]; then
  echo "  Manifest: $MANIFEST_PATH"
fi
