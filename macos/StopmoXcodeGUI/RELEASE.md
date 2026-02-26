# StopmoXcodeGUI Distribution

This project ships a standalone, signed `.app` bundled inside a notarizable `.dmg`.

## Prerequisites

- Xcode command line tools (`xcodebuild`, `codesign`, `hdiutil`)
- Apple Developer account with a `Developer ID Application` certificate
- `xcrun notarytool` and `xcrun stapler`

## 1) Build Standalone Release Artifacts

From repo root:

```bash
cd macos/StopmoXcodeGUI
chmod +x scripts/package_release.sh scripts/notarize_release.sh scripts/build_backend_runtime.sh scripts/create_dmg.sh
```

Build, bundle runtimes, sign, and produce DMG:

```bash
SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
VERSION="0.2.0" \
BUILD_NUMBER="1" \
scripts/package_release.sh
```

Outputs:

- `macos/StopmoXcodeGUI/dist/StopmoXcodeGUI.app`
- `macos/StopmoXcodeGUI/dist/StopmoXcodeGUI-<version>.dmg`
- `macos/StopmoXcodeGUI/dist/manifest.json` (runtime manifest)

Notes:

- Release build uses scheme `StopmoXcodeGUI-Release` by default.
- Backend runtimes are assembled per architecture (`arm64`, `x86_64`) under `Contents/Resources/backend/runtimes/`.
- `ALLOW_UNSIGNED=1` can be used only for local smoke builds.

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
  dist/StopmoXcodeGUI-0.2.0.dmg \
  dist/StopmoXcodeGUI.app
```

## 3) Optional: Build + Notarize in One Step

```bash
SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARIZE=1 \
NOTARY_PROFILE="stopmo-notary" \
VERSION="0.2.0" \
BUILD_NUMBER="1" \
scripts/package_release.sh
```

## Runtime Behavior

- Standalone app mode uses bundled backend launch script:
  - `Contents/Resources/backend/launch_bridge.sh`
- Development mode still works against external repo + `.venv` via `StopmoXcodeGUI-Dev` scheme.
