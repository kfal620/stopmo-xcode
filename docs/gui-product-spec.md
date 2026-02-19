# stopmo-xcode macOS GUI Product Spec (Phase 1)

## Goal

Evolve `stopmo-xcode` from CLI-only operation into a full macOS GUI app without
changing deterministic output guarantees or queue lifecycle semantics.

## Non-Negotiable Invariants

- Queue lifecycle remains: `detected -> decoding -> xform -> dpx_write -> done|failed`.
- White balance remains shot-level lock (never per-frame auto WB).
- Exposure remains shot-level policy (never per-frame normalization).
- Plate interpretation remains `ARRI LogC3 EI800 + AWG`.
- Display LUTs remain view-only and must not be baked into plate masters.

## Primary Users

- Stop-motion pipeline operators.
- Color/DIT-leaning technical artists validating plate outputs.
- Production coordinators who need live queue status and failure visibility.

## App Navigation (Top-Level Views)

1. `Setup`
2. `Project`
3. `Live Monitor`
4. `Shots`
5. `Queue`
6. `Tools`
7. `Logs & Diagnostics`
8. `History`

## Full Feature Coverage Matrix

### Setup

- Runtime checks: Python venv, `rawpy`, `PyOpenColorIO`, `tifffile`, `ffmpeg`,
  optional `exiftool`.
- Config file open/create from baseline sample.
- Directory access and writeability checks for source/work/output paths.

### Project

- Full edit surface for:
  - `watch.*`
  - `pipeline.*`
  - `output.*`
  - `log_level`, `log_file`
- Validation:
  - 3x3 matrix structure.
  - Required path fields.
  - Conditional requirements (e.g., OCIO config when `use_ocio=true`).
- Import/export presets and project config snapshots.

### Live Monitor

- Start/stop watch service.
- Real-time state counts and in-flight worker summary.
- Throughput, queue depth, and last-activity indicators.
- Active issues banner for failures/warnings.

### Shots

- Shot list with frame counts and assembly state (`pending`, `dirty`, `done`).
- Shot detail:
  - `manifest.json` summary (WB lock, exposure, pipeline hash, tool version).
  - output artifact links (DPX directory, frame JSON, truth frame, ProRes).

### Queue

- Full job table and filter/search by state/shot/source/error.
- Row detail with attempts, worker ID, timestamps, error text.
- Retry actions for failed work (future phase implementation).

### Tools

- `Transcode One`
- `Suggest Matrix` (including assumptions/notes/warnings and matrix apply flow)
- `DPX to ProRes` batch conversion

### Logs & Diagnostics

- Log stream with severity filtering.
- Structured diagnostics surfaces:
  - decode dependency failures
  - clipping warnings
  - NaN/Inf warnings
  - WB drift warnings
  - assembly failures

### History

- Prior run summaries with counts/timestamps/output roots.
- Reproducibility references from manifests (`pipeline_hash`, version).

## Status and Progress Requirements

- Per-job stage progress mapped from queue states.
- Per-operation IDs for non-watch tools (`transcode-one`, `suggest-matrix`,
  `dpx-to-prores`).
- Watch session telemetry:
  - queue depth
  - frames/min throughput
  - worker utilization
- Shot assembly status and retries visible by shot.

## UX Flow

1. User opens app and passes Setup health checks.
2. User configures or loads Project settings.
3. User starts Live Monitor watch session.
4. User tracks queue/shot progress and diagnostics.
5. User runs Tools as needed.
6. User inspects History and artifacts for handoff.

## Phase 1 Deliverables

- This product spec.
- Backend API contract document (`docs/gui-backend-api.md`).
- Feature-to-command parity mapping captured and tracked in docs.
