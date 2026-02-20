# GUI Phase 3 Unified Errors + Notifications

Phase 3 objective: keep blocking error alerts, add non-blocking toasts, and provide a notifications center panel for recent warnings/errors with copyable detail.

## Implemented

### 1) Notification model and lifecycle

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`

Added:

1. `NotificationKind` (`info`, `warning`, `error`)
2. `NotificationRecord` with:
   - title/message
   - likely cause
   - suggested action
   - timestamp label
3. Published state:
   - `notifications`
   - `activeToast`
4. Actions:
   - `presentError(...)` (blocking modal + notification record with hints)
   - `presentWarning(...)` (notification + toast)
   - `presentInfo(...)` (notification + toast)
   - `copyNotificationToPasteboard(...)`
   - `clearNotifications()`
   - `dismissToast()`

### 2) Actionable error hints

`presentError` now enriches alert content and notification details with:

1. likely cause
2. suggested action

Heuristics are included for common issues:

1. missing Python modules / venv mismatch
2. invalid repo root / bridge script missing
3. permission denied errors
4. FFmpeg/runtime dependency issues
5. decode/input errors

### 3) Non-blocking toast notifications

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`

Added:

1. top-right transient toast overlay (`NotificationToastView`)
2. auto-dismiss behavior (4s) with manual close
3. severity chip and concise message preview

### 4) Notifications center panel

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`

Added:

1. command-bar Notifications button with popover panel
2. recent notifications list with severity chips and timestamps
3. likely-cause + suggested-action context per item
4. per-item `Copy Details` action
5. `Clear All` action

### 5) Automatic warning surfacing

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`

Added automatic notification ingestion for:

1. new diagnostics warning signatures from `logsDiagnostics`
2. watch-start blocked/failed states
3. queue failed-count increases
4. diagnostics-bundle creation success info

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes with new Phase-3 smoke coverage.
