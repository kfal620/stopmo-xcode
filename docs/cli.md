# stopmo-xcode CLI And Developer Guide

This guide covers CLI usage, local setup, and parity/testing workflows.
The default end-user surface is the macOS app; see root `README.md` first.

## CLI Commands

- `watch`: watch source folder and process incoming RAW frames
- `transcode-one`: process a single frame for debugging/calibration
- `status`: inspect queue DB counts + recent jobs
- `suggest-matrix`: generate `pipeline.camera_to_reference_matrix` seed data
- `dpx-to-prores`: batch convert shot DPX sequences to ProRes 4444

Examples:

```bash
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli watch --config config/sample.yaml
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli status --config config/sample.yaml --json
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli suggest-matrix path/to/frame.CR3 --camera-make Canon --camera-model "EOS R" --write-json config/sample.matrix.json
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli dpx-to-prores path/to/output_root --framerate 24
```

## Local Setup

Create or refresh local virtualenv:

```bash
python3 -m venv --clear .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e ".[dev]"
```

Install runtime extras when needed:

```bash
.venv/bin/python -m pip install -e ".[watch,raw,ocio,io,video]"
```

Optional extras:

- `.[watch]` for watcher support (`watchdog`)
- `.[raw]` for LibRaw decode + EXIF metadata (`rawpy`, `exifread`)
- `.[ocio]` for OCIO processing
- `.[io]` for debug TIFF writer
- `.[video]` for imageio-ffmpeg fallback

If you see `bad interpreter` errors that reference an old repo path, recreate `.venv`.

## One-Command Launcher

Use `./stopmo` from repo root:

```bash
./stopmo --help
./stopmo watch --config config/sample.yaml
```

`./stopmo` will:

- create `.venv` if missing
- install runtime extras `.[watch,raw,ocio,io,video]`
- re-install when `pyproject.toml` changes
- run `.venv/bin/stopmo-xcode ...`

For ProRes assembly, `ffmpeg` resolution order is:

1. `STOPMO_XCODE_FFMPEG` env var
2. `ffmpeg` on `PATH`
3. bundled `imageio-ffmpeg` binary (from `.[video]`)

## Baseline Config And Quick Start

Baseline config lives at `config/sample.yaml`.

Start watcher:

```bash
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli watch --config config/sample.yaml
```

Inspect queue status:

```bash
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli status --config config/sample.yaml
```

## Determinism And Interpretation

- Queue lifecycle: `detected -> decoding -> xform -> dpx_write -> done` (or `failed`)
- Shot-level white-balance lock (no per-frame WB adaptation)
- No per-frame histogram/auto-normalization stage
- Deterministic exposure behavior:
  - base shot-level offset via `pipeline.exposure_offset_stops`
  - optional explicit metadata terms (`ISO`, `shutter`, `aperture`)
- Plate interpretation contract: `ARRI LogC3 EI800 + AWG`

Reference: `docs/interpretation-contract.md`

## Exposure Metadata Compensation

Optional terms:

- ISO: `log2(target_ei / frame_iso)`
- Shutter: `log2(target_shutter_s / frame_shutter_s)`
- Aperture: `2*log2(frame_aperture_f / target_aperture_f)`

Controls:

- `pipeline.auto_exposure_from_iso`
- `pipeline.auto_exposure_from_shutter` + `pipeline.target_shutter_s`
- `pipeline.auto_exposure_from_aperture` + `pipeline.target_aperture_f`

## Contrast Control

- `pipeline.contrast` (default `1.0`)
- `pipeline.contrast_pivot_linear` (default `0.18`)

## Batch DPX To ProRes

```bash
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli dpx-to-prores <input_dir> [--out-dir ...] [--framerate 24] [--no-overwrite] [--json]
```

Behavior:

- scans `*/dpx/*.dpx` sequences only
- ignores `truth_frame/`
- default output root is `<input_dir>/PRORES`
- output filenames are flattened by sequence stem (e.g. `PAW_0001.dpx` -> `PAW.mov`)

## Suggest Camera Matrix

```bash
PYTHONPATH=src .venv/bin/python -m stopmo_xcode.cli suggest-matrix path/to/frame.CR3 --camera-make Canon --camera-model "EOS R" --write-json config/sample.matrix.json
```

This prints a YAML snippet for `pipeline.camera_to_reference_matrix` and optionally writes
a JSON report with provenance/assumptions/warnings.

## GUI Bridge Parity Signoff

Run end-to-end CLI vs GUI-bridge parity checks:

```bash
.venv/bin/python qa/phase10_parity_signoff.py --repo-root "$PWD"
```

Outputs are written under `qa/reports/phase10_<timestamp>/`.
