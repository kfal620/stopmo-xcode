# StopmoXcodeGUI Agent Guide

Use this guide when working inside `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`.

## Build And Test

- Build: `swift build`
- Test: `swift test`
- Preferred cwd: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`

## High-Level Structure

- App entry: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/StopmoXcodeGUIApp.swift`
- App state + bridge orchestration: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`
- Root shell coordinator: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`
- Root shell subviews:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootSidebarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootCommandBarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootStatusBarView.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/NotificationViews.swift`
- Shared UI primitives and styling:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem.swift`

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
- Prefer adding reusable controls to `DesignSystem.swift` when behavior/styling repeats.
- Preserve current toolbar/notification spacing unless user requests visual changes.

## Tests To Run For UI/Core State Refactors

- Full package tests: `swift test`
- Focused tests:
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/ProjectEditorViewModelTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/NotificationPresenterStateTests.swift`
  - `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`

## Xcode Wrapper Notes

- Project wrapper: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/StopmoXcodeGUI.xcodeproj`
- If Swift files are added/removed, regenerate project wrapper:
  - `./scripts/generate_xcodeproj.py`
