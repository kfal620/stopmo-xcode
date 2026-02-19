# stopmo-xcode Architecture

## Modules

- `watcher/`: source folder polling + file completion detection
- `queue/`: SQLite queue, shot settings lock, resumable job states
- `decode/`: LibRaw decode adapters (`rawpy`) for CR2/CR3 and `.RAW` bridge
- `color/`: deterministic transform graph, optional OCIO path, LogC3 encode
- `write/`: 10-bit DPX writer + JSON sidecars + debug TIFF writer
- `assemble/`: optional ProRes 4444 and review exports (`ffmpeg`)
- `app_api.py`: GUI-facing backend facade with operation IDs, progress, and event polling
- `gui_bridge.py`: JSON bridge CLI used by SwiftUI shell for config, health, watch control, queue, and shot polling

## Queue State Machine

`detected -> decoding -> xform -> dpx_write -> done` (or `failed`)

- On startup, any inflight job (`decoding|xform|dpx_write`) is reset to `detected`.
- Source path uniqueness prevents duplicate frame jobs.

## Determinism Guarantees

- WB lock is persisted per shot in `shot_settings` and reused across all frames.
- Exposure offset is shot-level scalar only.
- No per-frame auto brightness or per-frame WB.
- Pipeline parameters are represented by a stable hash (`manifest.json`).

## Optional Dependencies

- `rawpy` / LibRaw: RAW decode
- `opencolorio`: OCIO transforms
- `tifffile`: debug TIFF output
- `ffmpeg`: ProRes assembly
