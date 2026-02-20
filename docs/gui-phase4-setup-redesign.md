# GUI Phase 4 Setup Redesign

Phase 4 objective: make Setup clearer for first-run and recovery workflows while preserving all existing setup functionality.

## Implemented

### 1) Setup information architecture refresh

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/SetupView.swift`

Setup is now organized into explicit cards:

1. `Paths`
2. `Permissions`
3. `Runtime Health`
4. `Dependency Checks`
5. `Config Validation`
6. `Watch Start Safety`

This keeps all existing actions while reducing ambiguity about where each setup task belongs.

### 2) Config bootstrap improvements (sample config flow)

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`

Added setup helpers:

1. `sampleConfigPath`
2. `useSampleConfig()`
3. `createConfigFromSample()`
4. `openConfigInFinder()`

These support:

1. quickly setting config path to `config/sample.yaml`
2. creating a config file from sample at the selected config path
3. opening current config (or containing directory) in Finder

### 3) Dependency table with remediation hints

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/SetupView.swift`

Dependency checks now show:

1. dependency name
2. availability status
3. detail (`Import OK` / `Import failed` / ffmpeg path)
4. targeted fix hint for common dependencies (`rawpy`, `OCIO`, `tifffile`, `ffmpeg`, `exiftool`)

### 4) Permissions clarity

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/SetupView.swift`

Permissions card now provides:

1. explicit workspace-access state chip
2. one clear `Grant Workspace Access…` action
3. concise guidance to keep watch paths under one workspace root

### 5) Setup parity retained

Existing setup features preserved:

1. Repo root browse
2. Config browse
3. Check runtime health
4. Load config
5. Save config
6. Validate config
7. Watch preflight
8. Workspace grant flow

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes (smoke tests remain green).
