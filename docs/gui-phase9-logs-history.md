# GUI Phase 9 Logs, Diagnostics, History UX

Phase 9 objective: make failures diagnosable and reproducibility checks practical without terminal access.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/LogsDiagnosticsView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/HistoryView.swift`

### 1) Structured log viewer with severity + field filters

Logs view now includes:

1. severity segment filters (`All`, `Error+Warn`, `Errors`, `Warnings`, `Info`)
2. logger field filter
3. message/timestamp search
4. server-side severity refresh input
5. structured log table columns (`timestamp`, `severity`, `logger`, `message`) with copy action per row

### 2) Diagnostics issue cards with remediation hints

Warnings/error signatures are now rendered as issue cards with:

1. severity + code chips
2. timestamp + message
3. likely-cause hint
4. suggested remediation action
5. copy action for support/escalation workflows

Issue code hints are included for clipping, NaN/Inf, WB drift, dependency errors, and decode failures.

### 3) History run cards + compare mode

History view now includes:

1. filter/search/sort controls
2. selectable run cards with quick actions (copy summary, open first output/manifest)
3. two-run compare mode with explicit delta rows for:
   - total jobs
   - failed jobs
   - state counts
   - output paths
   - pipeline hashes
   - tool versions
4. compare summary copy action

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes in `macos/StopmoXcodeGUI`.
