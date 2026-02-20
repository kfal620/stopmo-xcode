# GUI Phase 11 Performance + Resilience Hardening

Phase 11 objective: keep the GUI responsive under load, reduce refresh churn, and make bridge/watch failures recoverable directly from the app.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/BridgeClient.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/LiveMonitorView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/QueueView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ShotsView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/LogsDiagnosticsView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/HistoryView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`

### 1) Adaptive polling backoff + cancellation-safe monitoring

- Replaced fixed 1s live polling with adaptive intervals:
  - active watch/queue: fast polling
  - idle periods: slower polling
  - repeated failures: exponential backoff up to bounded interval
- Added monitor session-token guards to discard stale poll results after monitor restarts/stops.
- Added in-flight refresh gating to prevent overlapping bridge calls.
- Exposed monitoring health state (`healthy/degraded/recovery needed`, next poll, last failure) via `AppState`.

### 2) Safe start/stop/restart semantics for watch controls

- Watch start/stop/restart actions now suspend live polling while control operations run.
- Polling resumes only when the active section still requires monitoring.
- Added explicit watch restart action in app state for recovery workflows.

### 3) Bridge hardening to prevent UI hangs

- Added per-command bridge timeouts with command-appropriate budgets.
- Added incremental stdout/stderr draining during process execution to reduce pipe saturation risk.
- Timeouts now terminate stalled bridge commands and surface actionable error text.

### 4) Recovery UX in Live Monitor

- Added Recovery card with:
  - consecutive-failure/backoff indicators
  - last failure detail
  - next poll countdown
  - one-click actions (`Retry Now`, `Restart Monitoring`, `Restart Watch`, `Check Runtime Health`)

### 5) Pagination for heavy lists

- Added page size + previous/next pagination controls and visible-range indicators in:
  - Queue jobs table
  - Shots summary table
  - Logs structured entries
  - Diagnostics issues list
  - History run cards

### 6) Refresh churn cleanup

- Removed duplicate watch-preflight bridge call in `refreshWatchPreflight`.
- Reset pagination indexes when filter datasets change to avoid invalid page state and excess rerender churn.

## Validation

1. `swift build` passes in `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`.
2. `swift test` passes in `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI`.
