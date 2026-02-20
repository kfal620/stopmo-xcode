# GUI Phase 7 Shots + Queue Workflow

Phase 7 objective: make shot/queue triage fast and explicit without removing any existing functionality.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ShotsView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/QueueView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/BridgeClient.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/Models.swift`
- `/Users/kyle/Developer/stopmo-xcode/src/stopmo_xcode/gui_bridge.py`

### 1) Queue retry + snapshot export flow

- Added bridge command: `queue-retry-failed`.
- Supports retrying all failed jobs or selected failed job IDs.
- Queue retry clears stale worker/error fields and resets state to `detected`.
- Added GUI actions:
  - `Retry Failed`
  - `Retry Selected Failed`
  - `Export Queue Snapshot` (JSON)

### 2) Queue triage UX

- Queue view now includes:
  - search/filter/sort controls
  - selected-only mode
  - row-level actions (open source, copy source/error, retry row)
  - explicit selected-job detail panel with high-signal metadata and error text

### 3) Shots master-detail UX

- Shots view now includes:
  - search/filter/sort controls
  - issue/processing chips in header
  - selectable shot table with row-level actions
  - shot detail panel with:
    - frame-state summary
    - assembly state
    - effective exposure offset and locked WB multipliers (when present)
    - output/review media availability
    - Finder actions for shot folder, DPX, frame JSON, truth-frame, manifest, output/review MOV

### 4) Bridge contract coverage

- Added typed models + bridge method for queue retry result envelope.
- Updated bridge API docs to include `queue-retry-failed`.

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes in `macos/StopmoXcodeGUI`.
