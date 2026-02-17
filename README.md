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

## Notes

- Deterministic defaults: shot-level WB lock, no per-frame exposure normalization.
- Persistent SQLite queue supports crash-safe resume.
- DPX outputs are documented as `ARRI LogC3 EI800 + AWG` by interpretation contract.

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
stopmo-xcode dpx-to-prores path/to/output_root --framerate 24
```

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
