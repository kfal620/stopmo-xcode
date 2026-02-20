# GUI Phase 8 Tools Workflow Polish

Phase 8 objective: make one-off tools safer, clearer, and persistent for daily operations.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ToolsView.swift`

### 1) Guided forms with preflight validation

Each tool workflow now shows explicit preflight status with blockers/warnings:

1. `Transcode One` validates required input frame path.
2. `Suggest Matrix` validates required input frame path and report-path parent warnings.
3. `DPX To ProRes` validates required input directory and warns when no DPX files are detected.

Run actions are blocked when required preflight conditions fail.

### 2) Staged progress timeline

Tools now emit staged timeline entries for:

1. preflight blocks
2. run start
3. operation envelope milestones
4. completion/failure

Timeline entries are visible in a dedicated `Progress Timeline` card.

### 3) Result summaries with open/copy actions

All three tool flows now expose explicit post-run actions:

1. open/copy transcode output path
2. matrix summary + copy matrix values + optional report open
3. DPX batch summary + open/copy per-output actions

### 4) Persist recent inputs per tool

Tool fields are now persisted via app storage and include per-field recents menus:

1. last-used values survive app restarts
2. quick pick from recent input/output/report paths
3. recents can be cleared per field

### 5) Matrix apply-to-project preserved

`Apply Matrix To Project` remains available and now works directly off the latest suggested 3x3 payload.

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes in `macos/StopmoXcodeGUI`.
