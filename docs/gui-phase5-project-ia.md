# GUI Phase 5 Project Screen IA

Phase 5 objective: reduce cognitive load in Project editing while preserving all existing config controls.

## Implemented

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ProjectView.swift`

### 1) Segmented Project editor

Project editing is now segmented into:

1. Watch
2. Pipeline
3. Output
4. Logging
5. Presets

All existing config fields remain available (no field removed).

### 2) Dirty-state workflow

Added explicit local change tracking:

1. Saved/Unsaved status chip in header
2. Unsaved changes card with quick actions
3. `Save`, `Reload`, and `Discard` flow:
   - Save writes to config and updates baseline
   - Reload pulls from config and resets baseline
   - Discard restores baseline without hitting backend

### 3) Matrix editor UX upgrades

Added matrix tools in Pipeline section:

1. `Reset Identity` (sets 3x3 identity matrix)
2. `Paste 3x3` (parses clipboard text matrix)
3. `Copy 3x3` (copies current matrix to clipboard)

### 4) Validation visibility by section

Added per-section validation signal:

1. Validation strip across all segments (`Not Run` / `OK` / `N errors` / `N warnings`)
2. Selected section subtitle includes current validation status summary
3. Mapping of validation fields to Watch/Pipeline/Output/Logging domains

### 5) Local named presets

Added Presets section:

1. Save current config as named preset
2. Load selected preset into editor
3. Delete selected preset
4. Presets persisted in `UserDefaults` (local machine scope)

This is additive and does not change backend config contract.

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes (existing smoke suite remains green).
