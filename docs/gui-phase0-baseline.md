# GUI Baseline (Lifecycle IA Parity Lock)

Purpose: keep feature parity locked while using lifecycle information architecture.
Constraint: no feature removals are allowed in later UI phases.

## Coverage Matrix (CLI -> GUI)

| CLI / Backend Capability | GUI Hub / Panel | Primary Controls | Status |
| --- | --- | --- | --- |
| `watch` start/stop/state | Capture / Live Capture | `Start Watch`, `Stop Watch`, `Refresh` | Covered |
| `status` / queue status | Triage / Queue + Capture / Live Capture | Queue table + counters | Covered |
| `shots-summary` | Triage / Shots | Shot list + detail panel | Covered |
| `config-read` / `config-write` | Configure / Project Settings | Load/Save config | Covered |
| `health` | Configure / Workspace & Health | Runtime health check | Covered |
| `config-validate` | Configure / Workspace & Health | Config validation | Covered |
| `watch-preflight` | Configure / Workspace & Health + Capture / Live Capture | Preflight check and block reasons | Covered |
| `transcode-one` | Configure / Calibration | Transcode One form + run | Covered |
| `suggest-matrix` | Configure / Calibration | Suggest Matrix form + apply matrix | Covered |
| `dpx-to-prores` | Deliver / Day Wrap | DPX to ProRes form + run | Covered |
| `logs-diagnostics` | Triage / Diagnostics | Log viewer + severity filter | Covered |
| `copy-diagnostics-bundle` | Triage / Diagnostics | Copy diagnostics bundle | Covered |
| `history-summary` | Deliver / Run History | Run history list/summary | Covered |

## UI Surface Inventory

Primary sidebar hubs:
1. Configure
2. Capture
3. Triage
4. Deliver

Panel inventory:
1. Configure: Workspace & Health, Project Settings, Calibration
2. Capture: Live Capture
3. Triage: Shots, Queue, Diagnostics
4. Deliver: Day Wrap, Run History

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

## Automated Smoke Tests

Swift Package smoke tests are maintained at:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Tests/StopmoXcodeGUITests/Phase0SmokeTests.swift`

They assert:
1. Hub inventory is complete and ordered.
2. Hub identifiers are unique.
3. Lifecycle panel inventories are present.
4. Refresh routing and monitoring gating map correctly by hub/panel.
5. Tools mode filtering and Day Wrap DPX input prefill helpers behave correctly.
6. Interpretation-contract defaults remain stable (`EI800`, `ARRI_LogC3_EI800_AWG`, WB lock).
7. Critical `AppState` and `BridgeClient` actions remain callable.

Run:

```bash
cd /Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI
swift test
```

## Baseline Screenshot Checklist (Manual)

Capture before/after screenshots for each UI phase using the same project/config:
1. Configure / Workspace & Health (paths, permissions, health, validation, preflight)
2. Configure / Project Settings (watch/pipeline/output/logging/presets fields)
3. Configure / Calibration (Transcode One + Suggest Matrix)
4. Capture / Live Capture (idle)
5. Capture / Live Capture (watch running with activity)
6. Triage / Shots list + selected shot detail
7. Triage / Queue table with mixed states
8. Triage / Diagnostics with warnings visible
9. Deliver / Day Wrap with DPX batch panel and policy card
10. Deliver / Run History compare mode
11. Error alert (dismissible, non-obstructive)
