# GUI Phase 13 Pipeline Surface Refactor

Phase 13 objective: align the GUI with production time-horizons while preserving bridge/backend behavior.

## Responsibilities

1. Capture: live console focused on one active shot and ingest pace.
2. Triage: shot health board (card-first) with expandable detail and collapsed recovery drawer.
3. Deliver: shipping surface combining day-wrap batch controls and per-shot ProRes CTAs.

## Surface Map

1. Configure
   - Project Settings
   - Workspace & Health
   - Calibration
2. Capture
   - Live capture console (active-shot focus, live KPIs, watch runtime)
3. Triage
   - Shot Health Board (default)
   - Queue Workspace (advanced)
   - Diagnostics Workspace (advanced)
4. Deliver
   - Day Wrap (batch + per-shot shipping)
   - Run History

## Key UI Changes

1. Shared shot-health model introduced:
   - `ShotHealthState`: `clean`, `issues`, `inflight`, `queued`
   - readiness + deliverable helpers reused by Capture/Triage/Deliver
2. Capture:
   - active shot promoted to primary card
   - activity feed and watch log tail moved to collapsed disclosures
3. Triage:
   - table-first + quick-deliver removed from primary path
   - stacked health cards with inline expansion
   - collapsed recovery drawer with queue + diagnostics shortcuts
4. Deliver:
   - batch day-wrap card at top
   - per-shot deliverable cards with single primary `Deliver ProRes` action
   - non-ready shots shown under collapsed reasoned section
   - day-wrap timeline/events diagnostics retained under collapsed Advanced disclosure

## Parity Commitments

1. No backend API or bridge contract changes.
2. Queue retry/export, diagnostics bundle, and full queue/log workspaces remain available.
3. DPX batch and per-shot delivery both publish delivery operation envelopes.
4. Run History remains a dedicated Deliver tab.
5. Existing `tools.dpx.*` AppStorage keys remain unchanged.

## Validation

1. `swift build` passes for `macos/StopmoXcodeGUI`.
2. `swift test` passes, including:
   - `ShotHealthModelTests`
   - `DeliveryFlowTests`
   - existing smoke and regression tests.
