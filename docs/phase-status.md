# Phase Coverage Snapshot

## Phase 0

- Repo scaffolded with `src/`, `tests/`, `config/`, `docs/`.
- CLI entrypoint `stopmo-xcode` with:
  - `watch`
  - `transcode-one`
  - `status`
- Config loading, directory creation, and logging implemented.

## Phase 1

- Source folder watcher with stable-file completion policy (size + mtime age).
- Persistent SQLite queue with required states and failure state.
- Startup crash recovery resets inflight jobs to `detected`.
- Multiprocess worker pool (`spawn`) with configurable worker count.

## Phase 2

- LibRaw-backed decode path via `rawpy` for CR2/CR3.
- Metadata extraction includes WB, black/white levels, CFA, ISO/shutter/aperture.
- Shot-level WB lock persisted in DB and reused for each frame.
- Optional debug linear TIFF output.

## Phase 3

- Deterministic transform graph implemented.
- Optional OCIO path available when configured.
- Manual fallback path includes camera->reference matrix, ACES->AWG linear, exposure offset, optional match LUT, LogC3 EI800 encoding.
- LogC3 implementation isolated and unit-tested.

## Phase 4

- 10-bit RGB DPX writer with fixed naming `SHOT_####.dpx`.
- Per-shot `manifest.json` and optional per-frame JSON sidecars.
- Interpretation contract documented in docs.

## Phase 5

- Optional shot-complete assembly loop for LogC3/AWG ProRes 4444 using `ffmpeg`.
- Optional Rec709 review movie with provided show LUT.
- Handoff README generation.

## Phase 6

- Diagnostics: NaN/Inf and clipping warnings, WB drift warnings.
- Truth-frame pack generation (DPX + preview PNG).

## Current Gaps / Follow-up

- Dragonframe `.RAW` dedicated decoder is a placeholder and currently falls back to LibRaw compatibility only.
- OCIO correctness depends on user-provided config with valid input/output spaces.
- Golden-master regression harness and tight numeric validation data are not bundled yet.
- GUI phase-1 design-system foundation is now in place (`DesignSystem.swift`) and `SetupView` is migrated as the reference screen with no feature loss.
- GUI phase-2 app shell/navigation pass is now in place (sidebar icons/subtitles/badges, global command bar, project context chip, and keyboard shortcuts/command menus).
- GUI phase-3 notification model is now in place (blocking alerts + non-blocking toasts + notifications-center panel with copyable actionable details).
- GUI phase-4 setup redesign is now in place (paths/permissions/runtime/dependency/validation/preflight cards, sample-config bootstrap actions, and dependency fix hints).
- GUI phase-5 project IA pass is now in place (segmented editor, dirty-state save/discard flow, matrix reset/paste/copy controls, per-section validation status, and local named presets).
- GUI phase-6 live monitor upgrade is now in place (watch controls card with explicit blockers/errors, KPI strip, queue-depth trend sparkline, and filterable activity feed with pause/search).
- GUI phase-7 shots/queue workflow pass is now in place (master-detail shots triage, search/filter/sort in shots + queue, selected-row context panels, queue retry-selected/all failed actions, and queue snapshot export).
- GUI phase-8 tools workflow polish is now in place (preflight-gated tool forms, staged progress timeline, persistent per-tool recent inputs, and result open/copy actions while preserving apply-matrix-to-project).
- GUI phase-9 logs/diagnostics/history UX pass is now in place (structured log field filters, diagnostics issue cards with remediation hints, and history run-card compare mode across counts/failures/outputs/pipeline hash/tool version).
- GUI phase-10 accessibility/interaction pass is now in place (larger icon-action targets, explicit VoiceOver labels/hints, keyboard-first focus defaults for search-heavy screens, reduced-motion-aware toast behavior, and improved neutral chip contrast).
- GUI phase-11 performance/resilience hardening is now in place (adaptive live-poll backoff and recovery state, safe watch restart semantics with monitoring suspension, bridge command timeouts to prevent hangs, and pagination for queue/shots/logs/history heavy lists).
- GUI phase-12 lifecycle IA overhaul is now in place (4 top-level hubs: Configure/Capture/Triage/Deliver; panelized workflows; tools split into Calibration and Day Wrap; and command/menu/navigation updates aligned to production lifecycle mental model).
- GUI phase-13 pipeline surface refactor is now in place (Capture active-shot console, Triage shot-health board with recovery drawer, and Deliver shipping surface combining day-wrap batch + per-shot ProRes CTAs, with advanced diagnostics preserved under collapsed disclosures).
- GUI phase-13.1 density/hierarchy pass is now in place (compact stage headers, reduced vertical noise, relative timestamp labels, and one-primary-action card rhythm).
- GUI phase-13.3 premium visual pass is now in place (tokenized surface levels, cinematic dark polish, progressive sidebar detail behavior, and calmer command rail styling).
- GUI phase-13.4 delivery workspace redesign is now in place (two-column Day Wrap workspace, selectable ready-shot batch delivery, and always-visible run status/events panels).
- GUI phase-13.5 delivery modularization is now in place (`DeliveryDayWrap` split into focused pane/layout/formatting components with behavior parity).
- GUI phase-E tools workspace unification is now in place (`ToolsWorkspace` tabbed IA + extracted mapper/preflight/timeline/runner/viewmodel layers while preserving `ToolsView` compatibility API).
- GUI phase-F design-system modularization is now in place (`DesignSystem` split into token/component/style-focused files with contracts tests preserved).
- GUI phase-G app-state domain extraction is now in place (`AppStateDomain` reducers/services isolate monitoring, telemetry, notifications, and bridge orchestration helpers).
- GUI phase-H triage/capture modular follow-up is now in place (`TriageWorkspace` queue/diagnostics reducers extracted, capture sparkline component extracted, and legacy `ShotsView.swift` removed).
- GUI phase-14 shot preview rollout is now in place (backend first/latest JPEG preview generation, additive `shots-summary` preview fields, and context-aware thumbnails/lightbox in Capture latest vs Triage/Deliver first frame surfaces).
- macOS GUI shell now exposes lifecycle panels wired to `gui_bridge`, while preserving all prior feature capabilities and resilience checks (config validation, watch preflight, crash-recovery surfacing, safer watch start semantics).
- Phase-9 distribution scaffolding is added for macOS packaging/signing/notarization (`.app` bundle + zip, Developer ID codesign, notarytool submission/stapling scripts).
- Phase-10 parity/signoff harness is added under `qa/phase10_parity_signoff.py`, generating reproducible CLI-vs-GUI parity reports (`qa/reports/.../parity_signoff.md` + `.json`).
