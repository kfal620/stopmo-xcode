# StopmoXcodeGUI

SwiftUI shell for `stopmo-xcode`.

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
  - Tools view:
    - Transcode One workflow
    - Suggest Matrix workflow (with apply-to-project helper)
    - DPX to ProRes batch workflow (with completion summary)
  - Logs & Diagnostics view:
    - Structured log viewer with severity filtering
    - Warning surfacing (clipping, non-finite, WB drift, dependency/decode failures)
    - Diagnostics bundle export
  - History view:
    - Past run summary (start/end, counts, failures, output/repro metadata)
  - Resilience hardening:
    - Config validation panel in Setup
    - Watch preflight/blocker checks before start
    - Crash-recovery status surfaced in Live Monitor

## Packaging / Signing / Notarization

- Release workflow scripts and requirements are documented in:
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/RELEASE.md`
- Packaging assets:
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/packaging/Info.plist`
  - `/Users/kyle/Documents/Coding/stopmo-xcode/macos/StopmoXcodeGUI/packaging/entitlements.plist`
