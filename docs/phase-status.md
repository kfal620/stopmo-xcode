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
- macOS GUI shell now includes Setup + Project + Live Monitor + Queue + Shots + Tools + Logs/Diagnostics + History views wired to `gui_bridge`, plus phase-8 resilience checks (config validation, watch preflight, crash-recovery surfacing, safer watch start semantics).
- Phase-9 distribution scaffolding is added for macOS packaging/signing/notarization (`.app` bundle + zip, Developer ID codesign, notarytool submission/stapling scripts).
- Phase-10 parity/signoff harness is added under `qa/phase10_parity_signoff.py`, generating reproducible CLI-vs-GUI parity reports (`qa/reports/.../parity_signoff.md` + `.json`).
