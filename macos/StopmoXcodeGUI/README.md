# StopmoXcodeGUI

SwiftUI shell for `stopmo-xcode`.

## Architecture / Contributor Docs

- UI architecture map:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/docs/ui-architecture.md`
- macOS GUI agent guide:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/AGENTS.md`

## Build

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
swift build
```

## Test

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
swift test
```

Focused regression tests for recent UI refactors:

- `Tests/StopmoXcodeGUITests/ProjectEditorViewModelTests.swift`
- `Tests/StopmoXcodeGUITests/NotificationPresenterStateTests.swift`

Phase-0 UI parity/baseline reference:

- `/Users/kyle/Documents/Coding/stopmo-xcode/docs/gui-phase0-baseline.md`

## Xcode Project Wrapper

A proper macOS app target wrapper now exists:

- `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/StopmoXcodeGUI.xcodeproj`

Regenerate it (e.g. after adding/removing Swift files):

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
./scripts/generate_xcodeproj.py
```

Open in Xcode:

```bash
open /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/StopmoXcodeGUI.xcodeproj
```

Shared scheme `StopmoXcodeGUI` includes `STOPMO_XCODE_ROOT=$(SRCROOT)/../..`.

## Run

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
STOPMO_XCODE_ROOT=/Users/kyle/Documents/Coding/stopmo-xcode swift run StopmoXcodeGUI
```

## Notes

- The app calls Python bridge commands via:
  - `.venv/bin/python -m stopmo_xcode.gui_bridge ...`
- It expects the repo root to contain `.venv` and `pyproject.toml`.
- Current phase includes:
  - Lifecycle hubs:
    - Configure
      - Workspace & Health (runtime/dependency checks, validation, preflight)
      - Project Settings (full config edit/save)
      - Calibration (Transcode One + Suggest Matrix)
    - Capture
      - Live Capture (watch start/stop, queue progress, activity/log tail)
    - Triage
      - Shots + Queue + Diagnostics
    - Deliver
      - Day Wrap (DPX to ProRes batch-first)
      - Run History (run summary and compare)
  - Resilience hardening:
    - Config validation panel in Configure
    - Watch preflight/blocker checks before start
    - Crash-recovery status surfaced in Capture

## Packaging / Signing / Notarization

- Release workflow scripts and requirements are documented in:
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/RELEASE.md`
- Packaging assets:
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/packaging/Info.plist`
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/packaging/entitlements.plist`
