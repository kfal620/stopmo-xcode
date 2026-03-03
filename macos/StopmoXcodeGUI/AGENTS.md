# StopmoXcodeGUI Agent Guide

Use this guide when working inside `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`.

## Build And Test

- Build: `swift build`
- Test: `swift test`
- Preferred cwd: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`

## High-Level Structure

- App entry: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/StopmoXcodeGUIApp.swift`
- App state orchestration facade: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`
- AppState domain modules (services/reducers/planners):
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppStateDomain/`
- Root shell coordinator: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`
- Root shell subviews:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootSidebarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootCommandBarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootStatusBarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/NotificationViews.swift`
- Shared UI primitives and styling:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem/`
  - Compatibility shim: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem.swift`
- Delivery workspace modules:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DeliveryDayWrap/`
- Tools workspace modules:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ToolsWorkspace/`
- Triage operational modules:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/TriageWorkspace/`
- Capture console modules:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/CaptureConsole/`

## Lifecycle IA Baseline (Current)

- Hubs are lifecycle-first: `Configure -> Capture -> Triage -> Deliver`.
- Triage primary surface is `TriageShotHealthBoardView`; `QueueView` and `LogsDiagnosticsView` are advanced workspaces.
- Deliver primary surface is `DeliveryDayWrapView` (+ `Run History` tab).
- `ShotsView.swift` is removed from active code paths and should not be reintroduced without explicit product direction.

## Project Editor Architecture (Important)

- Project edits are draft-based via:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectEditorViewModel.swift`
- `ProjectView` should bind section UIs to `editor.draftConfig`, not directly to `state.config`.
- Save path: `state.saveConfig(config: editor.draftConfig)`.
- Reload/discard path must update draft baseline through `editor.acceptLoadedConfig(...)` / `editor.discardChanges()`.

### Do Not Reintroduce

- Direct field bindings in `ProjectView` to `state.config.*` for editable form controls.
- Implicit save semantics where typing mutates global config immediately.

## Notifications Architecture (Important)

- Central presenter state lives in `AppState`:
  - `notifications`, `activeToast`, `isNotificationsCenterPresented`
  - `notificationsBadgeText`, `notificationsBadgeTone`
- Presentation policy is centralized via:
  - `notificationPresentation()` modifier in `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/NotificationViews.swift`
- Command bar bell uses `NotificationBellButton` and should not duplicate popover state.

## UI Refactor Rules

- Keep `RootView` as coordinator; put UI details in focused files.
- Prefer adding reusable controls to `DesignSystem/` modules when behavior/styling repeats.
- Preserve current toolbar/notification spacing unless user requests visual changes.
- When adding filter/pagination/search logic for Queue/Diagnostics-style screens, prefer pure reducers in `TriageWorkspace/*/*Reducer.swift`.

## Window Chrome Customization

- Titlebar traffic-light controls are intentionally offset to align with the custom translucent sidebar/titlebar shell.
- Source of truth for shell offsets and spacing lives in:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootShellMetrics.swift`
- `RootWindowChromeConfigurator` is a controlled AppKit interop workaround:
  - It captures original system traffic-light button frames once per window.
  - It reapplies offsets relative to those original frames (never relative to current frames) to avoid drift after resize relayout.
- Safe tuning knobs:
  - `RootShellMetrics.titlebarControlsOffset`
  - `RootShellMetrics.sidebarToggleBaseLeading`
  - `RootShellMetrics.sidebarToggleBaseTop`
  - `RootShellMetrics.sidebarHeaderBaseClearance`
- Known risk area:
  - macOS/AppKit can relayout titlebar controls during and after live resize; if behavior regresses, inspect `RootWindowChromeConfigurator` observer lifecycle first.

## Tests To Run For UI/Core State Refactors

- Full package tests: `swift test`
- Focused tests:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/AppStateBridgeOrchestrationTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/LiveRefreshPlannerTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/WorkspaceConfigServiceTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/QueueFilterReducerTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/DiagnosticsFilterReducerTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/ProjectEditorViewModelTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/NotificationPresenterStateTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/TrafficLightFrameProjectorTests.swift`

## Xcode Wrapper Notes

- Project wrapper: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/StopmoXcodeGUI.xcodeproj`
- If Swift files are added/removed, regenerate project wrapper:
  - `./scripts/generate_xcodeproj.py`
- The project generator now emits nested source groups from on-disk folders. Keep files in real subfolders (`AppStateDomain`, `DeliveryDayWrap`, `DesignSystem`, `ToolsWorkspace`, `TriageWorkspace`, `CaptureConsole`) so navigator structure stays clean.
