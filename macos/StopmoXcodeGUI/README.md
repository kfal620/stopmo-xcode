# StopmoXcodeGUI

SwiftUI shell for `stopmo-xcode`.

## Build And Test

From this directory (`macos/StopmoXcodeGUI`):

```bash
swift build
swift test
```

Focused regression tests for recent UI refactors:

- `Tests/StopmoXcodeGUITests/ProjectEditorViewModelTests.swift`
- `Tests/StopmoXcodeGUITests/NotificationPresenterStateTests.swift`
- `Tests/StopmoXcodeGUITests/DeliveryRunReducerTests.swift`
- `Tests/StopmoXcodeGUITests/ToolsWorkspaceViewModelTests.swift`
- `Tests/StopmoXcodeGUITests/QueueFilterReducerTests.swift`
- `Tests/StopmoXcodeGUITests/DiagnosticsFilterReducerTests.swift`

## Xcode Project Wrapper

A proper macOS app target wrapper now exists:

- `StopmoXcodeGUI.xcodeproj`

Regenerate it (e.g. after adding/removing Swift files):

```bash
./scripts/generate_xcodeproj.py
```

Open in Xcode:

```bash
open StopmoXcodeGUI.xcodeproj
```

Shared schemes:

- `StopmoXcodeGUI-Dev`
  - external backend mode (`STOPMO_XCODE_ROOT=$(SRCROOT)/../..`)
- `StopmoXcodeGUI-Release`
  - bundled backend mode validation (`STOPMO_XCODE_RUNTIME_MODE=bundled`)
- `StopmoXcodeGUI`
  - compatibility alias to the dev scheme

## Run (Development)

From repo root:

```bash
cd macos/StopmoXcodeGUI
STOPMO_XCODE_ROOT="$(cd ../.. && pwd)" swift run StopmoXcodeGUI
```

## Notes

- Dev mode bridge path:
  - external repo backend (`.venv` + `src/stopmo_xcode/gui_bridge.py`)
- Release mode bridge path:
  - bundled launcher under app resources:
    - `Contents/Resources/backend/launch_bridge.sh`
- Workspace root is now independent from backend root. In bundled mode users choose workspace/config paths only.
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
      - Per-shot recovery actions (retry failed frames, restart clean rebuild, delete from DB, delete DB + outputs)
      - Right-rail Recovery drawer (collapsed by default, always visible)
    - Deliver
      - Day Wrap (DPX to ProRes batch-first)
      - Run History (run summary and compare)
  - Shot previews:
    - Capture active shot uses latest processed-frame preview.
    - Triage/Deliver shot rows use first-frame preview for shot identification.
    - Clickable thumbnails open a larger lightbox preview.
  - Refactored GUI module layout under `Sources/StopmoXcodeGUI/`:
    - `AppStateDomain` (reducers/services for `AppState` orchestration)
    - `CaptureConsole` (live capture-focused components)
    - `DeliveryDayWrap` (day-wrap shipping workspace components)
    - `DesignSystem` (tokenized visuals, surfaces, controls)
    - `ToolsWorkspace` (tabbed tools workspace + reducers/services)
    - `TriageWorkspace` (triage board + queue/diagnostics reducers)
  - Resilience hardening:
    - Config validation panel in Configure
    - Watch preflight/blocker checks before start
    - Crash-recovery status surfaced in Capture
  - Phase-0 UI parity/baseline reference:
    - `../../docs/gui-phase0-baseline.md`

## Packaging / Signing / Notarization

- Release workflow scripts and requirements are documented in:
  - `RELEASE.md`
- Packaging assets:
  - `packaging/Info.plist`
  - `packaging/entitlements.plist`
- Runtime/distribution scripts:
  - `scripts/build_backend_runtime.sh`
  - `scripts/create_dmg.sh`
  - `scripts/package_release.sh`
  - `scripts/notarize_release.sh`

## Architecture / Contributor Docs

- UI architecture map:
  - `docs/ui-architecture.md`
- macOS GUI agent guide:
  - `AGENTS.md`
