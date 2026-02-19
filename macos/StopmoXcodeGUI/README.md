# StopmoXcodeGUI

Phase 5 SwiftUI shell for `stopmo-xcode`.

## Build

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
swift build
```

## Run

```bash
cd /Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI
STOPMO_XCODE_ROOT=/Users/kyle/Documents/Coding/stopmo-xcode swift run StopmoXcodeGUI
```

## Notes

- The app calls Python bridge commands via:
  - `.venv/bin/python -m stopmo_xcode.gui_bridge ...`
- It expects the repo root to contain `.venv` and `pyproject.toml`.
- Current phase includes:
  - Sidebar navigation shell
  - Setup view (runtime/dependency checks)
  - Project view (full config edit and save)
  - Live Monitor view (watch start/stop, queue progress, activity/log tail)
  - Queue view (recent job table)
  - Shots view (per-shot progress and assembly state summary)
