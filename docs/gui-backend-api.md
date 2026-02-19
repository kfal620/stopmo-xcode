# stopmo-xcode GUI Backend API Contract (Phase 1)

This contract defines the Python-side API used by a future macOS GUI shell.
Initial implementation lives in:

- `/Users/kyle/Documents/Coding/stopmo-xcode/src/stopmo_xcode/app_api.py`

## Scope

- Reuse existing pipeline logic without behavior changes.
- Provide typed call/return shapes for GUI integration.
- Preserve CLI parity for all existing commands.

## Command Parity Mapping

- `watch` -> `run_watch(...)`
- `transcode-one` -> `run_transcode_one(...)`
- `status` -> `get_status(...)`
- `suggest-matrix` -> `suggest_matrix(...)`
- `dpx-to-prores` -> `convert_dpx_to_prores(...)`

## Data Contracts

### QueueJobStatus

- `id: int`
- `state: str`
- `shot: str`
- `frame: int`
- `source: str`
- `attempts: int`
- `last_error: str | None`
- `updated_at: str`

### QueueStatus

- `db_path: str`
- `counts: dict[str, int]`
- `recent: tuple[QueueJobStatus, ...]`

### MatrixSuggestResult

- `report: MatrixSuggestion`
- `payload: dict[str, object]`
- `json_report_path: Path | None`

### DpxToProresResult

- `input_dir: Path`
- `output_dir: Path`
- `outputs: tuple[Path, ...]`

## Function Contracts

### `run_watch(config_path)`

- Loads config.
- Configures logging using config values.
- Runs the watch service until interrupted.
- Side effects:
  - queue recovery (`reset_inflight_to_detected`)
  - file watching
  - worker process activity
  - optional assembly loop

### `run_transcode_one(config_path, input_path, output_dir=None) -> Path`

- Loads config + logging.
- Runs one-frame pipeline path through queue leasing and worker processing.
- Returns resolved output DPX path on success.

### `get_status(config_path, limit=20) -> QueueStatus`

- Loads config + logging.
- Reads queue DB state and recent jobs.
- Returns typed status payload for polling UI.

### `suggest_matrix(input_path, camera_make_override=None, camera_model_override=None, write_json_path=None) -> MatrixSuggestResult`

- Runs matrix suggestion analysis.
- Returns typed report and JSON payload.
- Optionally writes report JSON to disk.

### `convert_dpx_to_prores(input_dir, output_dir=None, framerate=24, overwrite=True) -> DpxToProresResult`

- Discovers sequences from nested `dpx/` folders.
- Converts to ProRes 4444 batch outputs.
- Returns input/output roots and generated clip paths.

## Error Model

- Existing domain exceptions are preserved.
- Caller should expect runtime errors for:
  - missing optional dependencies (`rawpy`, OCIO, ffmpeg)
  - decode failures
  - unsupported RAW formats
  - sequence name collisions in flat ProRes output

## Compatibility Notes

- This phase is an internal API contract for GUI integration.
- It intentionally mirrors current CLI behavior and side effects.
- Future phases may add operation IDs, event streams, and cancellable jobs
  without breaking existing function signatures where possible.
