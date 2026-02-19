# GUI Phase 0 Baseline (Parity Lock)

Purpose: lock feature parity and establish a baseline before UI polish work.  
Constraint: no feature removals are allowed in any later UI phase.

## Coverage Matrix (CLI -> GUI)

| CLI / Backend Capability | GUI Screen | Primary Controls | Status |
| --- | --- | --- | --- |
| `watch` start/stop/state | Live Monitor | `Start Watch`, `Stop Watch`, `Refresh` | Covered |
| `status` / queue status | Queue + Live Monitor | Queue table + counters | Covered |
| `shots-summary` | Shots | Shot list + detail panel | Covered |
| `config-read` / `config-write` | Setup + Project | Load/Save config | Covered |
| `health` | Setup | Runtime health check | Covered |
| `config-validate` | Setup | Config validation | Covered |
| `watch-preflight` | Setup + Live Monitor | Preflight check and block reasons | Covered |
| `transcode-one` | Tools | Transcode One form + run | Covered |
| `suggest-matrix` | Tools | Suggest Matrix form + apply matrix | Covered |
| `dpx-to-prores` | Tools | DPX to ProRes form + run | Covered |
| `logs-diagnostics` | Logs & Diagnostics | Log viewer + severity filter | Covered |
| `copy-diagnostics-bundle` | Logs & Diagnostics | Copy diagnostics bundle | Covered |
| `history-summary` | History | Run history list/summary | Covered |

## UI Surface Inventory

Primary sidebar sections (must remain present):
1. Setup
2. Project
3. Live Monitor
4. Shots
5. Queue
6. Tools
7. Logs & Diagnostics
8. History

## Critical Action Inventory

These actions must remain available and reachable after every UI phase:
1. Check runtime health
2. Load config
3. Save config
4. Start watch service
5. Stop watch service
6. Refresh live data
7. Refresh logs/diagnostics
8. Validate config
9. Refresh watch preflight
10. Refresh history
11. Copy diagnostics bundle
12. Transcode one
13. Suggest matrix
14. Apply suggested matrix to project config
15. DPX to ProRes

## Automated Smoke Tests (Phase 0)

Swift Package smoke tests were added at:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`

They assert:
1. Sidebar section inventory is complete and ordered.
2. Section identifiers are unique.
3. Interpretation-contract defaults remain stable (`EI800`, `ARRI_LogC3_EI800_AWG`, WB lock).
4. Critical `AppState` action methods are still callable.
5. Critical `BridgeClient` capability methods are still callable.

Run:

```bash
cd /Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI
swift test
```

## Baseline Screenshot Checklist (Manual)

Capture before/after screenshots for each UI phase using the same project/config:
1. Setup screen (health, paths, validation/preflight)
2. Project screen (watch/pipeline/output/logging/presets fields)
3. Live Monitor (idle)
4. Live Monitor (watch running with activity)
5. Shots list + selected shot detail
6. Queue table with mixed states
7. Tools: each of 3 tool panels populated
8. Logs & Diagnostics with warnings visible
9. History with at least one run
10. Error alert (dismissible, non-obstructive)
