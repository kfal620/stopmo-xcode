# StopmoXcodeGUI UI Architecture

This document summarizes the current GUI composition and the key rules for safe refactors.

## 1) Root Shell Composition

`RootView` is a coordinator, not a monolith.

- Coordinator: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`
- Sidebar: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootSidebarView.swift`
- Command bar: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootCommandBarView.swift`
- Status bar: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootStatusBarView.swift`
- Notifications presentation: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/NotificationViews.swift`

## 2) Shared UI Primitives

Reusable toolbar/status components are centralized in:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem.swift`

Notable primitives:

- `ToolbarActionCluster`
- `CommandIconButton`
- `CommandContextChip`
- `LiveStateChip`
- `StatusChip`

Rule: avoid re-implementing hover, badge, or chip behavior in feature views.

## 3) Notifications: Single Presentation Model

Notification state lives in `AppState`:

- `notifications`
- `activeToast`
- `isNotificationsCenterPresented`
- `notificationsBadgeText`
- `notificationsBadgeTone`

Presentation ownership:

- `NotificationBellButton` owns bell + badge + popover trigger
- `notificationPresentation()` owns toast docking/animation policy

Do not add per-view ad-hoc toast overlays.

## 4) Project Editor Draft Model

Project editing is draft-based and explicit.

- View model: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectEditorViewModel.swift`
- Coordinator view: `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectView.swift`

Edit flow:

1. Load from disk into app state.
2. Seed draft via `editor.acceptLoadedConfig(state.config)`.
3. Edit `editor.draftConfig` in section subviews.
4. Save explicitly via `state.saveConfig(config: editor.draftConfig)`.
5. Reset baseline with `editor.acceptLoadedConfig(state.config)` after successful save.

Never bind editable project fields directly to `state.config`.

## 5) Project Section Decomposition

Project sections are split into dedicated views:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectWatchSectionView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectPipelineSectionView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectOutputSectionView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectLoggingSectionView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectPresetsSectionView.swift`

`ProjectView` should stay focused on composition and orchestration.

## 6) Regression Test Coverage

Core tests for the refactored architecture:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/ProjectEditorViewModelTests.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/NotificationPresenterStateTests.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`

Run all with:

```bash
cd /Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI
swift test
```
