# StopmoXcodeGUI Distribution

This project ships a macOS `.app` bundle and a zip archive suitable for notarization.

## Prerequisites

- Xcode command line tools
- Apple Developer account (Developer ID cert)
- `codesign`, `xcrun notarytool`, `xcrun stapler`

## 1) Build + Package

From repo root:

```bash
cd macos/StopmoXcodeGUI
chmod +x scripts/package_release.sh scripts/notarize_release.sh
```

Unsigned package:

```bash
scripts/package_release.sh
```

Signed package:

```bash
SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
VERSION="0.1.0" \
BUILD_NUMBER="1" \
scripts/package_release.sh
```

Outputs:

- `macos/StopmoXcodeGUI/dist/StopmoXcodeGUI.app`
- `macos/StopmoXcodeGUI/dist/StopmoXcodeGUI-<version>.zip`

## 2) Notarize + Staple

Store credentials once:

```bash
xcrun notarytool store-credentials stopmo-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Submit and staple:

```bash
NOTARY_PROFILE="stopmo-notary" \
scripts/notarize_release.sh \
  dist/StopmoXcodeGUI-0.1.0.zip \
  dist/StopmoXcodeGUI.app
```

## Notes

- Bundle metadata lives in `packaging/Info.plist`.
- Hardened runtime entitlements are in `packaging/entitlements.plist`.
- This GUI uses a Python backend bridge and expects a compatible runtime environment at execution time.
