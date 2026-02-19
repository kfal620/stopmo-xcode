#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <zip-path> [app-path]" >&2
  exit 1
fi

ZIP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APP_PATH="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "${NOTARY_PROFILE}" ]]; then
  echo "NOTARY_PROFILE is required (xcrun notarytool keychain profile name)." >&2
  exit 1
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "zip not found: ${ZIP_PATH}" >&2
  exit 1
fi

echo "Submitting for notarization: ${ZIP_PATH}"
xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

if [[ -n "${APP_PATH}" ]]; then
  if [[ ! -d "${APP_PATH}" ]]; then
    echo "app bundle not found for stapling: ${APP_PATH}" >&2
    exit 1
  fi
  echo "Stapling ticket: ${APP_PATH}"
  xcrun stapler staple "${APP_PATH}"
  xcrun stapler validate "${APP_PATH}"
fi

echo "Notarization complete."
