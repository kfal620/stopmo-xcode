#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <artifact-path> [app-path]" >&2
  exit 1
fi

ARTIFACT_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APP_PATH="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required (xcrun notarytool keychain profile name)." >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

if [[ -n "$APP_PATH" ]]; then
  APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "app bundle not found for stapling: $APP_PATH" >&2
    exit 1
  fi
fi

echo "Submitting for notarization: $ARTIFACT_PATH"
xcrun notarytool submit "$ARTIFACT_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

if [[ -n "$APP_PATH" ]]; then
  echo "Stapling app ticket: $APP_PATH"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
fi

if [[ "$ARTIFACT_PATH" == *.dmg ]]; then
  echo "Stapling artifact ticket: $ARTIFACT_PATH"
  xcrun stapler staple "$ARTIFACT_PATH"
  xcrun stapler validate "$ARTIFACT_PATH"
fi

echo "Notarization complete."
