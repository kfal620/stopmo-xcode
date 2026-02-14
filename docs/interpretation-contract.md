# stopmo-xcode Interpretation Contract

## Scope

This document defines how `stopmo-xcode` encodes output plates and how downstream tools should interpret them.

## Plate Contract (authoritative)

- Image sequence format: DPX, 10-bit, RGB.
- Pixel encoding: **ARRI LogC3 EI800**.
- Primaries/gamut: **ARRI Wide Gamut (AWG)**.
- Exposure policy: fixed, shot-level only (`exposure_offset_stops`), never per-frame normalization.
- White balance policy: fixed, shot-level lock (from first frame or configured reference), never per-frame WB.

## Critical Rule

Do not rely on DPX metadata auto-detection in compositing/editorial apps.
Always set interpretation explicitly to `LogC3/AWG`.

## Viewing Rule

- Editorial/viewing transform is external (show LUT): `LogC3/AWG -> Rec709`.
- The LUT is for display only and must not be baked into plate masters.

## Sidecar Truth

Per-shot `manifest.json` is the source of truth for:

- locked WB multipliers
- exposure offset
- target EI
- pipeline hash + tool version

Per-frame JSON (optional) records source filename/hash and decode diagnostics.

## Reproducibility

Given identical source files and identical config/pipeline hash, outputs are expected to be byte-stable except for header timestamps in container formats.
