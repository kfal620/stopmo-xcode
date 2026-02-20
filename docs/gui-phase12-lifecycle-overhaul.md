# GUI Phase 12 Lifecycle IA Overhaul

Phase 12 objective: shift the macOS GUI from capability-first sections to a production lifecycle mental model while preserving all backend features and critical actions.

## Scope

Updated files:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/Models.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/AppState.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootSidebarView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/RootCommandBarView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/StopmoXcodeGUIApp.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/ConfigureHubView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/CaptureHubView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/TriageHubView.swift`
- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DeliverHubView.swift`
- Embedded-mode updates to existing screen views and `ToolsView` mode splitting.

## Before -> After IA Map

Top-level navigation:

1. `Setup` -> `Configure / Workspace & Health`
2. `Project` -> `Configure / Project Settings`
3. `Tools (Transcode One, Suggest Matrix)` -> `Configure / Calibration`
4. `Live Monitor` -> `Capture / Live Capture`
5. `Shots` -> `Triage / Shots`
6. `Queue` -> `Triage / Queue`
7. `Logs & Diagnostics` -> `Triage / Diagnostics`
8. `Tools (DPX To ProRes)` -> `Deliver / Day Wrap`
9. `History` -> `Deliver / Run History`

## Interaction Changes

1. New top-level hubs: `Configure`, `Capture`, `Triage`, `Deliver`.
2. New panel selectors inside hubs (chip-based).
3. Stage-specific header accents and hierarchy via lifecycle design components.
4. Cross-stage CTAs:
   - Capture -> Open Triage / Open Deliver
   - Triage -> Open Deliver (Day Wrap)
   - Deliver -> Back to Capture
5. Command bar context now shows `Hub / Panel`.
6. Keyboard navigation changed:
   - `Cmd+1` Configure
   - `Cmd+2` Capture
   - `Cmd+3` Triage
   - `Cmd+4` Deliver
   - Panel-level navigation is available under `Navigate` submenus.

## Delivery Workflow Updates

1. Deliver is batch-first:
   - `DPX To ProRes` is primary in Day Wrap.
2. Day Wrap default behavior:
   - If DPX input field is empty, it resolves from configured `watch.output_dir`.
3. Shot-complete auto assembly remains available:
   - Configure > Project Settings > Output > `Write ProRes On Shot Complete`.
4. Deliver shows a policy card with current auto-assembly status and `Edit in Configure` shortcut.

## State/Behavior Refactor

1. `AppSection` replaced by:
   - `LifecycleHub`
   - `ConfigurePanel`
   - `TriagePanel`
   - `DeliverPanel`
2. `AppState.selectedSection` replaced by:
   - `selectedHub`
   - `selectedConfigurePanel`
   - `selectedTriagePanel`
   - `selectedDeliverPanel`
3. Refresh routing is panel-aware via `refreshKindForCurrentSelection()`.
4. Monitoring gating is panel-aware:
   - Capture: always monitored
   - Triage: monitored for Shots/Queue only
   - Configure/Deliver: not continuously monitored

## ToolsView Split

1. `ToolsView` adds:
   - `mode: ToolsMode` (`all`, `utilitiesOnly`, `deliveryOnly`)
   - `embedded: Bool`
2. Shared helpers added for testability:
   - `visibleToolKinds(for:)`
   - `resolvedDpxInputDir(currentInputDir:configOutputDir:)`

## Parity Guarantee

No backend bridge or CLI contract changed. The overhaul is UI IA/UX + app-state routing only.
All critical actions from baseline remain reachable.

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes in `macos/StopmoXcodeGUI`.
3. Smoke tests updated for:
   - lifecycle hub inventory/order
   - panel inventory
   - refresh routing mapping
   - monitoring gating mapping
   - tools mode filtering
   - day-wrap DPX prefill helper

## Manual Checklist

1. Configure workspace paths and config; run health + validation + preflight.
2. Capture: start watch and verify queue/KPI/activity updates.
3. Triage: inspect shots, retry failed queue rows, review diagnostics and export bundle.
4. Deliver: run Day Wrap DPX->ProRes and verify output list/actions.
5. Deliver: open Run History and compare two runs.
6. Verify command bar start/stop/refresh and Hub/Panel context chip.
