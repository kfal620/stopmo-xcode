# GUI Phase 6 Live Monitor Upgrade

Phase 6 objective: make live operations status clearer and faster to triage from a single screen.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/LiveMonitorView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`

### 1) Watch controls row with explicit start blockers

Live Monitor now includes a dedicated controls card with:

1. `Start Watch`
2. `Stop Watch`
3. `Refresh`
4. explicit status chips for running/stopped/blocked/error
5. clear blocker/launch-error text when start is blocked or launch fails

### 2) KPI strip

Added a horizontal KPI strip with:

1. queue state counts (`detected`, `decoding`, `xform`, `dpx_write`, `done`, `failed`)
2. throughput (`frames/min`)
3. in-flight worker load (`inflight / maxWorkers`)
4. ETA heuristic
5. time since last frame update

### 3) Queue depth trend

Added rolling queue-depth trend chart:

1. sparkline over recent samples
2. current depth
3. peak depth
4. sample count

Telemetry backing is tracked in `AppState`:

1. `queueDepthTrend`
2. `throughputFramesPerMinute`
3. `lastFrameAt`

### 4) Filterable activity feed

Added activity controls:

1. filter (`All`, `Warnings`, `Errors`, `System`)
2. pause updates
3. search

Feed remains backed by existing `liveEvents`, with local filtering/pausing in UI.

### 5) Existing behavior preserved

No backend API contract changes were made. Existing operations remain unchanged:

1. watch start/stop/state polling
2. queue/shots snapshot refresh
3. log tail display

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes (smoke suite remains green).
