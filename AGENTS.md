# stopmo-xcode Agent Guide

Use this file as the default operating guide for agents working in this repo.

## Environment

- Preferred environment path: `/Users/kyle/Documents/Coding/stopmo-xcode/.venv`
- Use explicit venv binaries for Python tooling:
  - `.venv/bin/python`
  - `.venv/bin/pip`
  - `.venv/bin/pytest`
  - `.venv/bin/stopmo-xcode`

If `.venv` is missing:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e ".[dev]"
```

Install runtime extras only when needed:

```bash
.venv/bin/python -m pip install -e ".[watch,raw,ocio,io,video]"
```

## Preferred Command Paths

- For normal development/test work, use `.venv/bin/...` commands directly.
- For end-to-end CLI runs, prefer `./stopmo ...` (bootstraps runtime extras and runs the venv CLI).
- Use `/Users/kyle/Documents/Coding/stopmo-xcode/config/sample.yaml` as the baseline config.

## Fast Workflow

1. Run tests:
   - `.venv/bin/python -m pytest -q`
2. Run focused tests while iterating:
   - `.venv/bin/python -m pytest -q tests/test_queue_db.py`
   - `.venv/bin/python -m pytest -q tests/test_color_pipeline.py`
   - `.venv/bin/python -m pytest -q tests/test_worker_exposure.py`
   - `.venv/bin/python -m pytest -q tests/test_prores_batch.py`
3. Validate CLI surface after command/config changes:
   - `.venv/bin/stopmo-xcode --help`

## Codebase Map

- CLI entrypoint: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/cli.py`
- Service orchestration (watch loop, workers, assembly): `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/service.py`
- Worker processing pipeline: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/worker.py`
- Queue and state handling: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/queue/`
- Decode adapters: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/decode/`
- Color and transforms: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/color/`
- Writers/manifests/DPX: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/write/`
- ProRes assembly: `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/assemble/`

## Project Invariants (Do Not Break)

- Determinism is a core requirement:
  - Shot-level WB lock; never per-frame WB auto-adjust.
  - Shot-level exposure policy; no per-frame normalization.
- Queue lifecycle must remain stable: `detected -> decoding -> xform -> dpx_write -> done` (or `failed`).
- Output interpretation contract is authoritative:
  - DPX is LogC3 EI800 + AWG.
  - Do not bake display LUTs into plate masters.
  - Reference: `/Users/kyle/Documents/Coding/stopmo-xcode/docs/interpretation-contract.md`

## Change Discipline

- If you change CLI arguments/behavior:
  - update `/Users/kyle/Documents/Coding/stopmo-xcode/README.md`
  - update/add CLI tests
- If you change config schema/defaults:
  - update `/Users/kyle/Documents/Coding/stopmo-xcode/config/sample.yaml`
  - update `/Users/kyle/Documents/Coding/stopmo-xcode/tests/test_config.py`
- If you touch queue/worker state transitions:
  - run `tests/test_queue_db.py`
  - run `tests/test_worker_exposure.py`
- If you touch color math or transforms:
  - run `tests/test_color_pipeline.py`
  - run `tests/test_arri_logc3.py`
- If you touch DPX/ProRes outputs:
  - run `tests/test_dpx_writer.py`
  - run `tests/test_prores_batch.py`
