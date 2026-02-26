# stopmo-xcode Agent Guide

Use this file as the default operating guide for agents working in this repo.

## Scope And Path Conventions

- Current workspace root: `/Users/kyle/Developer/stopmo-xcode`
- Prefer repo-relative paths in guidance and updates (`config/sample.yaml`, `src/stopmo_xcode/...`).
- Do not introduce new references to `/Users/kyle/Documents/Coding/stopmo-xcode` in docs or commands for this workspace.

## Environment

- Canonical virtualenv path: `.venv`
- Prefer explicit Python-module invocations:
  - `.venv/bin/python -m pip ...`
  - `.venv/bin/python -m pytest ...`
  - `PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli ...` (reliable CLI module invocation)

Bootstrap or refresh the environment:

```bash
python3 -m venv --clear .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e ".[dev]"
```

Install runtime extras when needed:

```bash
.venv/bin/python -m pip install -e ".[watch,raw,ocio,io,video]"
```

If commands fail with `bad interpreter` pointing to an old path, treat the venv as stale and run the refresh sequence above.

## Preferred Command Paths

- For development/test work, use `.venv/bin/python -m ...` commands.
- For end-to-end CLI runs, prefer `./stopmo ...` after the venv is healthy.
- Baseline config: `config/sample.yaml`.

## Fast Workflow

1. Environment sanity:
   - `.venv/bin/python -m pip --version`
   - `.venv/bin/python -m pip install -e ".[dev]"`
2. Full test run:
   - `.venv/bin/python -m pytest -q`
3. Focused test runs by subsystem:
   - Queue/state: `.venv/bin/python -m pytest -q tests/test_queue_db.py`
   - Worker exposure policy: `.venv/bin/python -m pytest -q tests/test_worker_exposure.py`
   - Watcher completion: `.venv/bin/python -m pytest -q tests/test_completion_tracker.py`
   - Shot naming: `.venv/bin/python -m pytest -q tests/test_shot_naming.py`
   - Color pipeline + LogC3: `.venv/bin/python -m pytest -q tests/test_color_pipeline.py tests/test_arri_logc3.py`
   - Matrix suggestion: `.venv/bin/python -m pytest -q tests/test_matrix_suggest.py`
   - EXIF metadata parsing: `.venv/bin/python -m pytest -q tests/test_exif_metadata.py`
   - DPX writer: `.venv/bin/python -m pytest -q tests/test_dpx_writer.py`
   - ProRes batch assembly: `.venv/bin/python -m pytest -q tests/test_prores_batch.py`
   - Bridge/API surfaces: `.venv/bin/python -m pytest -q tests/test_gui_bridge.py tests/test_app_api.py`
   - Formatting utilities: `.venv/bin/python -m pytest -q tests/test_formatting.py`
4. Validate CLI/bridge surfaces after command/config changes:
   - `PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli --help`
   - `PYTHONPATH=src .venv/bin/python -m stopmo_xcode.gui_bridge --help`
   - `./stopmo --help` (launcher smoke check)
5. GUI/bridge parity signoff when touching parity-critical flows:
   - `.venv/bin/python qa/phase10_parity_signoff.py --repo-root "$PWD"`

## Codebase Map

- CLI entrypoint: `src/stopmo_xcode/cli.py`
- Watch service orchestration: `src/stopmo_xcode/service.py`
- Worker pipeline: `src/stopmo_xcode/worker.py`
- Queue + shot state store: `src/stopmo_xcode/queue/`
- Decode + metadata adapters: `src/stopmo_xcode/decode/`
- Color transforms + matrix suggestion: `src/stopmo_xcode/color/`
- Writers/manifests/DPX: `src/stopmo_xcode/write/`
- ProRes assembly: `src/stopmo_xcode/assemble/`
- GUI backend API facade: `src/stopmo_xcode/app_api.py`
- GUI JSON bridge CLI: `src/stopmo_xcode/gui_bridge.py`
- Watcher completion tracking: `src/stopmo_xcode/watcher/`
- Config loading/schema: `src/stopmo_xcode/config.py`
- Baseline config: `config/sample.yaml`
- Interpretation contract: `docs/interpretation-contract.md`
- Architecture notes: `docs/architecture.md`
- macOS GUI guide: `macos/StopmoXcodeGUI/AGENTS.md`

## Project Invariants (Do Not Break)

- Queue lifecycle for frame jobs must remain:
  - `detected -> decoding -> xform -> dpx_write -> done` (or `failed`)
- Startup crash recovery must keep resetting inflight jobs (`decoding|xform|dpx_write`) back to `detected`.
- Determinism requirements:
  - WB behavior is shot-locked (no per-frame WB adaptation).
  - No per-frame histogram/auto-normalization pass.
  - Exposure behavior is deterministic:
    - Base shot-level exposure offset is stable.
    - Optional metadata compensation terms (`ISO`, `shutter`, `aperture`) may be enabled explicitly and are formula-based, not adaptive normalization.
- Output interpretation contract is authoritative:
  - DPX plates are `ARRI LogC3 EI800 + AWG`.
  - Never bake display LUTs into plate masters.
  - Reference: `docs/interpretation-contract.md`

## Change Discipline

- If you change CLI arguments or behavior (`cli.py`):
  - update `README.md` command docs
  - run relevant bridge/API parity tests:
    - `tests/test_gui_bridge.py`
    - `tests/test_app_api.py`
  - run CLI/bridge help smoke checks
- If you change GUI bridge payloads/commands (`gui_bridge.py`) or app API operation flows (`app_api.py`):
  - run:
    - `tests/test_gui_bridge.py`
    - `tests/test_app_api.py`
    - `qa/phase10_parity_signoff.py` signoff run
- If you change config schema/defaults (`config.py`):
  - update `config/sample.yaml`
  - run:
    - `tests/test_config.py`
    - `tests/test_gui_bridge.py` (config read/write/validate surfaces)
- If you touch queue/worker state transitions:
  - run:
    - `tests/test_queue_db.py`
    - `tests/test_worker_exposure.py`
- If you touch watcher/completion or shot inference:
  - run:
    - `tests/test_completion_tracker.py`
    - `tests/test_shot_naming.py`
- If you touch color math, LogC3, or matrix suggestion:
  - run:
    - `tests/test_color_pipeline.py`
    - `tests/test_arri_logc3.py`
    - `tests/test_matrix_suggest.py`
- If you touch decode metadata parsing:
  - run:
    - `tests/test_exif_metadata.py`
- If you touch DPX/ProRes outputs:
  - run:
    - `tests/test_dpx_writer.py`
    - `tests/test_prores_batch.py`
- If you touch formatting helpers used in metadata output:
  - run:
    - `tests/test_formatting.py`
- If you touch macOS SwiftUI shell code:
  - follow `macos/StopmoXcodeGUI/AGENTS.md`
  - run `swift test` from `macos/StopmoXcodeGUI`

## Known Drift Notes

- Some docs still contain old absolute path examples under `/Users/kyle/Documents/Coding/stopmo-xcode`; prefer repo-relative commands or `--repo-root "$PWD"`.
- `docs/architecture.md` currently describes exposure as shot-level scalar only, while current worker code supports optional deterministic metadata compensation terms. If you edit exposure behavior, keep docs in sync.
