# stopmo-xcode

`stopmo-xcode` is a cross-platform CLI for watching Dragonframe capture folders and deterministically transcoding incoming RAW still frames into ARRI-style LogC3/AWG deliverables.

## Commands

- `stopmo-xcode watch --config config/sample.yaml`
- `stopmo-xcode transcode-one path/to/frame.CR3 --config config/sample.yaml`
- `stopmo-xcode status --config config/sample.yaml`
- `stopmo-xcode suggest-matrix path/to/frame.CR3 --camera-make Canon --camera-model "EOS R" --write-json config/sample.matrix.json`
- `stopmo-xcode dpx-to-prores path/to/output_root --framerate 24`

## Install (editable)

```bash
python -m pip install -e .[dev,raw,ocio,io]
```

Optional extras:

- `.[watch]` for event-driven watcher support (`watchdog`)
- `.[raw]` for LibRaw decode support (`rawpy`)
- `.[ocio]` for OCIO-based transforms
- `.[io]` for debug TIFF writer

## One-Command Launcher (Phase 1)

Use the repo launcher to bootstrap everything and run the CLI in one step:

```bash
./stopmo watch --config config/sample.yaml
```

What `./stopmo` does automatically:

- creates `.venv` if missing
- installs runtime extras: `.[watch,raw,ocio,io,video]`
- re-installs when `pyproject.toml` changes
- runs `.venv/bin/stopmo-xcode ...`

For ProRes assembly, `ffmpeg` is resolved in this order:

1. `STOPMO_XCODE_FFMPEG` (if set)
2. `ffmpeg` on `PATH`
3. bundled `imageio-ffmpeg` binary from `.[video]`

## Notes

- Deterministic defaults: shot-level WB lock, no per-frame exposure normalization.
- Persistent SQLite queue supports crash-safe resume.
- DPX outputs are documented as `ARRI LogC3 EI800 + AWG` by interpretation contract.

## Exposure Metadata Compensation

Exposure offset can combine multiple optional metadata terms:

- ISO term: `log2(target_ei / frame_iso)`
- Shutter term: `log2(target_shutter_s / frame_shutter_s)`
- Aperture term: `2*log2(frame_aperture_f / target_aperture_f)`

Enable/disable each term with:

- `pipeline.auto_exposure_from_iso`
- `pipeline.auto_exposure_from_shutter` with `pipeline.target_shutter_s`
- `pipeline.auto_exposure_from_aperture` with `pipeline.target_aperture_f`

## Contrast Control

Pipeline contrast is applied in LogC3 domain with a pivot:

- `pipeline.contrast` (default `1.0`, where `1.0` is no change)
- `pipeline.contrast_pivot_linear` (default `0.18`)

## Quick Start

```bash
stopmo-xcode watch --config config/sample.yaml
```

In another terminal, drop RAW frames into `sandbox/incoming`.

Check queue state:

```bash
stopmo-xcode status --config config/sample.yaml
```

## Batch DPX To ProRes

Convert nested shot DPX sequences to ProRes 4444 (LogC3 values preserved, no LUT applied):

```bash
stopmo-xcode dpx-to-prores <path/to/input_folder> --framerate 24
```

Example:
stopmo-xcode dpx-to-prores <input_dir> [--out-dir ...] [--framerate 24] [--no-overwrite] [--json]

- Scans only `*/dpx/*.dpx` sequences (ignores `truth_frame/`).
- Output root defaults to `path/to/output_root/PRORES`.
- Output clip name is the DPX sequence stem minus trailing frame number.
  - Example: `PAW_0001.dpx` -> `PAW.mov`
- Clips are written flat into `PRORES` (no shot subfolders).

## Suggest Camera Matrix

Use one representative RAW still from your camera to generate a starting
`pipeline.camera_to_reference_matrix` for ACES2065-1:

```bash
stopmo-xcode suggest-matrix path/to/frame.CR3 --camera-make Canon --camera-model "EOS R" --write-json config/sample.matrix.json
```

The command prints a YAML snippet you can paste into `config/sample.yaml` and
writes a JSON report with source/provenance, assumptions, notes, and warnings.
An example report schema is provided at `config/sample.matrix.json`.
