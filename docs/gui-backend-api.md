# GUI Backend API

`stopmo_xcode.app_api` provides a Python API intended for GUI integration.

## Synchronous Operations

- `run_watch(config_path)`
- `run_transcode_one(config_path, input_path, output_dir=None)`
- `get_status(config_path, limit=20)`
- `suggest_matrix(input_path, camera_make_override=None, camera_model_override=None, write_json_path=None)`
- `convert_dpx_to_prores(input_dir, output_dir=None, framerate=24, overwrite=True)`

## Phase 3 Async Runtime

- `start_watch_operation(...) -> operation_id`
- `start_transcode_one_operation(...) -> operation_id`
- `start_suggest_matrix_operation(...) -> operation_id`
- `start_dpx_to_prores_operation(...) -> operation_id`
- `cancel_operation(operation_id) -> bool`
- `get_operation(operation_id) -> OperationSnapshot | None`
- `list_operations(limit=100) -> tuple[OperationSnapshot, ...]`
- `wait_for_operation(operation_id, timeout_seconds=None) -> OperationSnapshot | None`
- `poll_operation_events(after_seq=0, operation_id=None, limit=200) -> tuple[OperationEvent, ...]`

## Operation Status Values

- `pending`
- `running`
- `succeeded`
- `failed`
- `cancelled`

## Event Stream Notes

- Events are in-memory and monotonic by `seq`.
- Use `after_seq` polling to stream incrementally from GUI.
- Watch operations emit periodic `queue_status` events with state counts.
- DPX-to-ProRes emits `dpx_sequence_complete` events per sequence.

## GUI Bridge CLI (Phase 4)

SwiftUI shell integration uses:

- `python -m stopmo_xcode.gui_bridge config-read --config <path>`
- `python -m stopmo_xcode.gui_bridge config-write --config <path>` (JSON stdin)
- `python -m stopmo_xcode.gui_bridge health [--config <path>]`
- `python -m stopmo_xcode.gui_bridge queue-status --config <path> [--limit N]`
- `python -m stopmo_xcode.gui_bridge shots-summary --config <path> [--limit N]`
- `python -m stopmo_xcode.gui_bridge watch-start --config <path>`
- `python -m stopmo_xcode.gui_bridge watch-stop --config <path> [--timeout S]`
- `python -m stopmo_xcode.gui_bridge watch-state --config <path> [--limit N] [--tail N]`

All commands emit JSON payloads for direct GUI decoding.
