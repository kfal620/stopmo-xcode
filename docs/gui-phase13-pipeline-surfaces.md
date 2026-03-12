# GUI Phase 13 Pipeline Surface Refactor

Phase 13 objective: align the GUI with production time-horizons while preserving bridge/backend behavior.
The current pass keeps the internal `triage` identifiers for compatibility, but the user-facing hub name is now `Review`.

## Responsibilities

1. Configure: unified setup workspace for recipe, output, health, and calibration.
2. Capture: active-shot monitor centered on one live shot and ingest pace.
3. Review: list-detail shot workspace with recovery tools and advanced queue/diagnostics surfaces.
4. Deliver: shipping desk for day-wrap planning, run control, history, and output review.

## Surface Map

1. Configure
   - Unified setup canvas with left section rail
   - Sticky footer for save/discard/validate/preflight
   - Persistent deterministic contract inspector
2. Capture
   - Active-shot hero and inline alert banner
   - Right inspector for watch state, queue health, and recipe summary
   - Bottom console dock for activity, watch log, and diagnostics
3. Review
   - Grouped shot list (`Issues`, `Inflight`, `Ready`, `Completed`)
   - Selected-shot detail canvas
   - Recovery/actions inspector
   - Queue Workspace (advanced)
   - Diagnostics Workspace (advanced)
4. Deliver
   - Deliverable shot list
   - Day-wrap run plan with inline advanced settings
   - Run summary inspector
   - Bottom timeline/diagnostics console
   - Run History

## Key UI Changes

1. Shared shot-health model remains the backbone:
   - `ShotHealthState`: `clean`, `issues`, `inflight`, `queued`
   - readiness + deliverable helpers reused by Capture/Review/Deliver
2. Shell redesign:
   - quiet dark stage rail
   - compact toolbar
   - light main canvas
   - right inspector column
   - bottom console dock that stays collapsed until needed
3. Configure:
   - project, health, presets, and calibration now live in one setup workspace
   - `ProjectEditorViewModel` remains the draft source of truth
4. Capture:
   - active shot promoted to a single hero surface
   - start-blocked, launch-failed, and recovery states collapsed into one inline alert banner
   - secondary telemetry moved into the inspector and console
5. Review:
   - card wall replaced by a three-pane list-detail workspace
   - stable shot grouping/filtering/selection handled by `ReviewWorkspaceReducer`
   - recovery actions move into the inspector/context menus instead of every row
4. Deliver:
   - day wrap becomes a shipping desk with list, plan, inspector, and timeline
   - advanced batch settings move inline under the run plan
   - blocked shots move below the ready list in a collapsed section
   - the console auto-opens while a delivery run is active

## Parity Commitments

1. No backend API or bridge contract changes.
2. Queue retry/export, diagnostics bundle, and full queue/log workspaces remain available.
3. DPX batch and per-shot delivery both publish delivery operation envelopes.
4. Run History remains a dedicated Deliver tab.
5. Existing `tools.dpx.*` AppStorage keys remain unchanged.
6. Internal enum/storage cases remain stable (`LifecycleHub.triage`, `TriagePanel`, etc.).

## Validation

1. `swift build` passes for `macos/StopmoXcodeGUI`.
2. `swift test` passes, including:
   - `ShotHealthModelTests`
   - `DeliveryFlowTests`
   - `ReviewWorkspaceReducerTests`
   - `ConfigureSectionMappingTests`
   - existing smoke and regression tests.
