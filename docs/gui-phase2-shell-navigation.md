# GUI Phase 2 App Shell + Navigation

Phase 2 objective: improve global shell usability and navigation speed without removing any existing features.

## Implemented

### 1) Sidebar polish

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/Models.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`

Changes:

1. Added per-section icon metadata (`AppSection.iconName`).
2. Added per-section subtitle metadata (`AppSection.subtitle`).
3. Sidebar rows now show icon + title + subtitle.
4. Sidebar badges now surface high-signal state:
   - Live Monitor: `RUN` when watch is running.
   - Queue: failed count badge (`N!`) when failures exist.
   - Logs & Diagnostics: warning count badge when warnings exist.
   - History: run-count badge when available.

### 2) Global command bar

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`

Changes:

1. Added a persistent top command bar in detail pane.
2. Added persistent project context chip:
   - repo root basename
   - config file basename
3. Added global actions (all existing capabilities preserved):
   - Start Watch
   - Stop Watch
   - Refresh (context-sensitive by selected section)
   - Validate Config
   - Check Runtime Health
4. Added watch state chip in command bar (`Watch Running` / `Watch Stopped`).

### 3) Keyboard shortcuts and command menus

Updated:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/StopmoXcodeGUIApp.swift`

Command menu: `Stopmo`

1. Start Watch: `Cmd+Option+S`
2. Stop Watch: `Cmd+Option+.`
3. Refresh Current Section: `Cmd+Option+R`
4. Validate Config: `Cmd+Option+V`
5. Check Runtime Health: `Cmd+Option+H`

Command menu: `Navigate`

1. Setup: `Cmd+1`
2. Project: `Cmd+2`
3. Live Monitor: `Cmd+3`
4. Shots: `Cmd+4`
5. Queue: `Cmd+5`
6. Tools: `Cmd+6`
7. Logs & Diagnostics: `Cmd+7`
8. History: `Cmd+8`

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes (Phase 0 smoke tests unchanged).
3. All prior views and actions remain available.
