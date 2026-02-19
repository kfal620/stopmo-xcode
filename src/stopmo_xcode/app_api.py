from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
from pathlib import Path
import threading
import uuid
from typing import Any, Callable

from stopmo_xcode.assemble import AssemblyError, convert_dpx_sequences_to_prores, discover_dpx_sequences
from stopmo_xcode.color.matrix_suggest import MatrixSuggestion, suggest_camera_to_reference_matrix
from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB
from stopmo_xcode.service import run_watch_service, transcode_one as service_transcode_one
from stopmo_xcode.utils.logging_utils import configure_logging


logger = logging.getLogger(__name__)

TERMINAL_OPERATION_STATES = {"succeeded", "failed", "cancelled"}


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class QueueJobStatus:
    id: int
    state: str
    shot: str
    frame: int
    source: str
    attempts: int
    last_error: str | None
    updated_at: str


@dataclass(frozen=True)
class QueueStatus:
    db_path: str
    counts: dict[str, int]
    recent: tuple[QueueJobStatus, ...]


@dataclass(frozen=True)
class MatrixSuggestResult:
    report: MatrixSuggestion
    payload: dict[str, object]
    json_report_path: Path | None


@dataclass(frozen=True)
class DpxToProresResult:
    input_dir: Path
    output_dir: Path
    outputs: tuple[Path, ...]


@dataclass(frozen=True)
class OperationEvent:
    seq: int
    operation_id: str
    timestamp_utc: str
    event_type: str
    message: str | None
    payload: dict[str, object] | None


@dataclass(frozen=True)
class OperationSnapshot:
    id: str
    kind: str
    status: str
    progress: float
    created_at_utc: str
    started_at_utc: str | None
    finished_at_utc: str | None
    cancel_requested: bool
    cancellable: bool
    error: str | None
    metadata: dict[str, object]
    result: dict[str, object] | None


@dataclass
class _OperationRuntime:
    id: str
    kind: str
    status: str
    progress: float
    created_at_utc: str
    metadata: dict[str, object]
    started_at_utc: str | None = None
    finished_at_utc: str | None = None
    error: str | None = None
    result: dict[str, object] | None = None
    cancel_requested: bool = False
    cancellable: bool = False
    stop_event: threading.Event | None = None
    worker_thread: threading.Thread | None = None


class OperationCancelled(RuntimeError):
    pass


class _OperationManager:
    def __init__(self, max_events: int = 5000) -> None:
        self._lock = threading.RLock()
        self._operations: dict[str, _OperationRuntime] = {}
        self._events: list[OperationEvent] = []
        self._next_seq = 1
        self._max_events = int(max_events)

    def create(
        self,
        kind: str,
        metadata: dict[str, object] | None = None,
        cancellable: bool = False,
    ) -> _OperationRuntime:
        now = _utc_now_iso()
        operation_id = f"op_{uuid.uuid4().hex}"
        runtime = _OperationRuntime(
            id=operation_id,
            kind=kind,
            status="pending",
            progress=0.0,
            created_at_utc=now,
            metadata=metadata or {},
            cancellable=bool(cancellable),
            stop_event=threading.Event() if cancellable else None,
        )
        with self._lock:
            self._operations[operation_id] = runtime
            self._emit_locked(operation_id, "operation_created", payload={"kind": kind, "metadata": runtime.metadata})
        return runtime

    def bind_thread(self, operation_id: str, worker_thread: threading.Thread) -> None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is not None:
                runtime.worker_thread = worker_thread

    def mark_started(self, operation_id: str) -> None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return
            runtime.status = "running"
            runtime.started_at_utc = _utc_now_iso()
            self._emit_locked(operation_id, "operation_started")

    def emit(
        self,
        operation_id: str,
        event_type: str,
        message: str | None = None,
        payload: dict[str, object] | None = None,
    ) -> None:
        with self._lock:
            if operation_id not in self._operations:
                return
            self._emit_locked(operation_id, event_type, message=message, payload=payload)

    def set_progress(
        self,
        operation_id: str,
        progress: float,
        *,
        event_type: str | None = None,
        message: str | None = None,
        payload: dict[str, object] | None = None,
    ) -> None:
        clamped = max(0.0, min(1.0, float(progress)))
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return
            runtime.progress = clamped
            if event_type is not None:
                progress_payload: dict[str, object] = {"progress": clamped}
                if payload:
                    progress_payload.update(payload)
                self._emit_locked(operation_id, event_type, message=message, payload=progress_payload)

    def succeed(self, operation_id: str, result: dict[str, object] | None = None) -> None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return
            runtime.status = "succeeded"
            runtime.progress = 1.0
            runtime.result = result
            runtime.finished_at_utc = _utc_now_iso()
            self._emit_locked(operation_id, "operation_succeeded", payload=result)

    def cancel_complete(self, operation_id: str, result: dict[str, object] | None = None) -> None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return
            runtime.status = "cancelled"
            runtime.result = result
            runtime.finished_at_utc = _utc_now_iso()
            self._emit_locked(operation_id, "operation_cancelled", payload=result)

    def fail(self, operation_id: str, error: str) -> None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return
            runtime.status = "failed"
            runtime.error = str(error)
            runtime.finished_at_utc = _utc_now_iso()
            self._emit_locked(operation_id, "operation_failed", message=runtime.error)

    def request_cancel(self, operation_id: str) -> bool:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None or not runtime.cancellable:
                return False
            if runtime.status in TERMINAL_OPERATION_STATES:
                return False
            runtime.cancel_requested = True
            if runtime.stop_event is not None:
                runtime.stop_event.set()
            self._emit_locked(operation_id, "operation_cancel_requested")
            return True

    def get(self, operation_id: str) -> OperationSnapshot | None:
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return None
            return self._to_snapshot(runtime)

    def list(self, limit: int = 100) -> tuple[OperationSnapshot, ...]:
        with self._lock:
            runtimes = sorted(
                self._operations.values(),
                key=lambda op: op.created_at_utc,
                reverse=True,
            )
            return tuple(self._to_snapshot(op) for op in runtimes[: max(1, int(limit))])

    def poll_events(
        self,
        *,
        after_seq: int = 0,
        operation_id: str | None = None,
        limit: int = 200,
    ) -> tuple[OperationEvent, ...]:
        with self._lock:
            out: list[OperationEvent] = []
            for event in self._events:
                if event.seq <= after_seq:
                    continue
                if operation_id is not None and event.operation_id != operation_id:
                    continue
                out.append(event)
                if len(out) >= max(1, int(limit)):
                    break
            return tuple(out)

    def wait(self, operation_id: str, timeout_seconds: float | None = None) -> OperationSnapshot | None:
        worker: threading.Thread | None = None
        with self._lock:
            runtime = self._operations.get(operation_id)
            if runtime is None:
                return None
            worker = runtime.worker_thread

        if worker is not None:
            worker.join(timeout=timeout_seconds)
        return self.get(operation_id)

    def _to_snapshot(self, runtime: _OperationRuntime) -> OperationSnapshot:
        return OperationSnapshot(
            id=runtime.id,
            kind=runtime.kind,
            status=runtime.status,
            progress=runtime.progress,
            created_at_utc=runtime.created_at_utc,
            started_at_utc=runtime.started_at_utc,
            finished_at_utc=runtime.finished_at_utc,
            cancel_requested=runtime.cancel_requested,
            cancellable=runtime.cancellable,
            error=runtime.error,
            metadata=dict(runtime.metadata),
            result=dict(runtime.result) if runtime.result is not None else None,
        )

    def _emit_locked(
        self,
        operation_id: str,
        event_type: str,
        *,
        message: str | None = None,
        payload: dict[str, object] | None = None,
    ) -> None:
        event = OperationEvent(
            seq=self._next_seq,
            operation_id=operation_id,
            timestamp_utc=_utc_now_iso(),
            event_type=event_type,
            message=message,
            payload=dict(payload) if payload is not None else None,
        )
        self._next_seq += 1
        self._events.append(event)
        if len(self._events) > self._max_events:
            self._events = self._events[-self._max_events :]


_OPERATIONS = _OperationManager()


def _collect_status_from_db_path(db_path: Path, limit: int = 20) -> QueueStatus:
    db = QueueDB(db_path)
    try:
        counts = db.stats()
        jobs = db.recent_jobs(limit=limit)
        return QueueStatus(
            db_path=str(db_path),
            counts=counts,
            recent=tuple(
                QueueJobStatus(
                    id=job.id,
                    state=job.state,
                    shot=job.shot_name,
                    frame=job.frame_number,
                    source=job.source_path,
                    attempts=job.attempts,
                    last_error=job.last_error,
                    updated_at=job.updated_at,
                )
                for job in jobs
            ),
        )
    finally:
        db.close()


def _start_async_operation(
    *,
    kind: str,
    metadata: dict[str, object] | None,
    cancellable: bool,
    runner: Callable[[_OperationRuntime], dict[str, object] | None],
) -> str:
    runtime = _OPERATIONS.create(kind=kind, metadata=metadata, cancellable=cancellable)

    def _target() -> None:
        _OPERATIONS.mark_started(runtime.id)
        try:
            result = runner(runtime)
            if runtime.cancel_requested and runtime.cancellable:
                _OPERATIONS.cancel_complete(runtime.id, result=result)
            else:
                _OPERATIONS.succeed(runtime.id, result=result)
        except OperationCancelled as exc:
            _OPERATIONS.cancel_complete(runtime.id, result={"reason": str(exc)})
        except Exception as exc:
            logger.exception("operation %s failed kind=%s", runtime.id, runtime.kind)
            _OPERATIONS.fail(runtime.id, str(exc))

    thread = threading.Thread(target=_target, name=f"stopmo-op-{runtime.kind}-{runtime.id}", daemon=True)
    _OPERATIONS.bind_thread(runtime.id, thread)
    thread.start()
    return runtime.id


def run_watch(config_path: str | Path) -> None:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)
    run_watch_service(config)


def run_transcode_one(
    config_path: str | Path,
    input_path: str | Path,
    output_dir: str | Path | None = None,
) -> Path:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)

    resolved_input = Path(input_path).expanduser().resolve()
    resolved_output = Path(output_dir).expanduser().resolve() if output_dir else None
    return service_transcode_one(config, input_path=resolved_input, output_dir=resolved_output)


def get_status(config_path: str | Path, limit: int = 20) -> QueueStatus:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)
    return _collect_status_from_db_path(config.watch.db_path, limit=limit)


def suggest_matrix(
    input_path: str | Path,
    camera_make_override: str | None = None,
    camera_model_override: str | None = None,
    write_json_path: str | Path | None = None,
) -> MatrixSuggestResult:
    resolved_input = Path(input_path).expanduser().resolve()
    report = suggest_camera_to_reference_matrix(
        resolved_input,
        reference_space="ACES2065-1",
        camera_make_override=camera_make_override,
        camera_model_override=camera_model_override,
    )
    payload: dict[str, object] = report.to_json_dict()

    json_path = Path(write_json_path).expanduser().resolve() if write_json_path else None
    if json_path is not None:
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        payload["json_report_path"] = str(json_path)

    return MatrixSuggestResult(report=report, payload=payload, json_report_path=json_path)


def convert_dpx_to_prores(
    input_dir: str | Path,
    output_dir: str | Path | None = None,
    framerate: int = 24,
    overwrite: bool = True,
) -> DpxToProresResult:
    resolved_input = Path(input_dir).expanduser().resolve()
    resolved_output = Path(output_dir).expanduser().resolve() if output_dir else None
    outputs = convert_dpx_sequences_to_prores(
        input_root=resolved_input,
        output_root=resolved_output,
        framerate=int(framerate),
        overwrite=bool(overwrite),
    )
    final_output_dir = (resolved_output or (resolved_input / "PRORES")).resolve()
    return DpxToProresResult(
        input_dir=resolved_input,
        output_dir=final_output_dir,
        outputs=tuple(Path(p).resolve() for p in outputs),
    )


def start_watch_operation(
    config_path: str | Path,
    *,
    status_poll_interval_seconds: float = 1.0,
    recent_limit: int = 20,
) -> str:
    resolved_config_path = Path(config_path).expanduser().resolve()

    def _runner(runtime: _OperationRuntime) -> dict[str, object]:
        config = load_config(resolved_config_path)
        configure_logging(config.log_level, config.log_file)

        _OPERATIONS.set_progress(runtime.id, 0.01, event_type="watch_bootstrap")
        stop_event = runtime.stop_event or threading.Event()

        status_thread_stop = threading.Event()

        def _status_loop() -> None:
            while not status_thread_stop.is_set():
                try:
                    status = _collect_status_from_db_path(config.watch.db_path, limit=recent_limit)
                    counts = dict(status.counts)
                    total = sum(counts.values())
                    completed = int(counts.get("done", 0)) + int(counts.get("failed", 0))
                    inflight = (
                        int(counts.get("detected", 0))
                        + int(counts.get("decoding", 0))
                        + int(counts.get("xform", 0))
                        + int(counts.get("dpx_write", 0))
                    )
                    progress = (float(completed) / float(total)) if total > 0 else 0.0
                    _OPERATIONS.set_progress(runtime.id, progress)
                    _OPERATIONS.emit(
                        runtime.id,
                        "queue_status",
                        payload={
                            "counts": counts,
                            "completed": completed,
                            "inflight": inflight,
                            "total": total,
                        },
                    )
                except Exception as exc:
                    _OPERATIONS.emit(runtime.id, "queue_status_error", message=str(exc))
                status_thread_stop.wait(max(0.1, float(status_poll_interval_seconds)))

        poller = threading.Thread(target=_status_loop, name=f"stopmo-watch-status-{runtime.id}", daemon=True)
        poller.start()

        try:
            run_watch_service(config, shutdown_event=stop_event)
        finally:
            status_thread_stop.set()
            poller.join(timeout=2.0)

        final_status = _collect_status_from_db_path(config.watch.db_path, limit=recent_limit)
        _OPERATIONS.emit(runtime.id, "watch_stopped", payload={"counts": dict(final_status.counts)})
        return {
            "config_path": str(resolved_config_path),
            "db_path": str(config.watch.db_path),
            "counts": dict(final_status.counts),
        }

    return _start_async_operation(
        kind="watch",
        metadata={"config_path": str(resolved_config_path)},
        cancellable=True,
        runner=_runner,
    )


def start_transcode_one_operation(
    config_path: str | Path,
    input_path: str | Path,
    output_dir: str | Path | None = None,
) -> str:
    resolved_config_path = Path(config_path).expanduser().resolve()
    resolved_input_path = Path(input_path).expanduser().resolve()
    resolved_output_dir = Path(output_dir).expanduser().resolve() if output_dir else None

    def _runner(runtime: _OperationRuntime) -> dict[str, object]:
        _OPERATIONS.set_progress(runtime.id, 0.1, event_type="transcode_begin")
        output_path = run_transcode_one(
            config_path=resolved_config_path,
            input_path=resolved_input_path,
            output_dir=resolved_output_dir,
        )
        _OPERATIONS.set_progress(runtime.id, 0.95, event_type="transcode_done")
        return {
            "config_path": str(resolved_config_path),
            "input_path": str(resolved_input_path),
            "output_path": str(output_path),
        }

    return _start_async_operation(
        kind="transcode_one",
        metadata={
            "config_path": str(resolved_config_path),
            "input_path": str(resolved_input_path),
            "output_dir": str(resolved_output_dir) if resolved_output_dir else None,
        },
        cancellable=False,
        runner=_runner,
    )


def start_suggest_matrix_operation(
    input_path: str | Path,
    camera_make_override: str | None = None,
    camera_model_override: str | None = None,
    write_json_path: str | Path | None = None,
) -> str:
    resolved_input_path = Path(input_path).expanduser().resolve()
    resolved_write_json = Path(write_json_path).expanduser().resolve() if write_json_path else None

    def _runner(runtime: _OperationRuntime) -> dict[str, object]:
        _OPERATIONS.set_progress(runtime.id, 0.1, event_type="matrix_suggest_begin")
        result = suggest_matrix(
            input_path=resolved_input_path,
            camera_make_override=camera_make_override,
            camera_model_override=camera_model_override,
            write_json_path=resolved_write_json,
        )
        _OPERATIONS.set_progress(runtime.id, 0.95, event_type="matrix_suggest_done")
        output: dict[str, object] = dict(result.payload)
        if result.json_report_path is not None:
            output["json_report_path"] = str(result.json_report_path)
        return output

    return _start_async_operation(
        kind="suggest_matrix",
        metadata={
            "input_path": str(resolved_input_path),
            "camera_make_override": camera_make_override,
            "camera_model_override": camera_model_override,
            "write_json_path": str(resolved_write_json) if resolved_write_json else None,
        },
        cancellable=False,
        runner=_runner,
    )


def start_dpx_to_prores_operation(
    input_dir: str | Path,
    output_dir: str | Path | None = None,
    framerate: int = 24,
    overwrite: bool = True,
) -> str:
    resolved_input = Path(input_dir).expanduser().resolve()
    resolved_output = Path(output_dir).expanduser().resolve() if output_dir else None

    def _runner(runtime: _OperationRuntime) -> dict[str, object]:
        _OPERATIONS.set_progress(runtime.id, 0.05, event_type="dpx_to_prores_begin")
        sequences = discover_dpx_sequences(resolved_input)
        total_sequences = len(sequences)
        _OPERATIONS.emit(runtime.id, "dpx_sequences_discovered", payload={"total_sequences": total_sequences})

        completed_sequences = 0
        total_scale = max(1, total_sequences)

        def _on_sequence_complete(seq: Any, out_mov: Path) -> None:
            nonlocal completed_sequences
            completed_sequences += 1
            progress = 0.1 + (0.85 * (float(completed_sequences) / float(total_scale)))
            _OPERATIONS.set_progress(runtime.id, progress)
            _OPERATIONS.emit(
                runtime.id,
                "dpx_sequence_complete",
                payload={
                    "completed_sequences": completed_sequences,
                    "total_sequences": total_sequences,
                    "shot_name": str(seq.shot_name),
                    "sequence_name": str(seq.sequence_name),
                    "output_path": str(out_mov),
                },
            )

        try:
            outputs = convert_dpx_sequences_to_prores(
                input_root=resolved_input,
                output_root=resolved_output,
                framerate=int(framerate),
                overwrite=bool(overwrite),
                on_sequence_complete=_on_sequence_complete,
                should_stop=lambda: bool(runtime.stop_event is not None and runtime.stop_event.is_set()),
            )
        except AssemblyError as exc:
            if runtime.cancel_requested and "cancel" in str(exc).lower():
                raise OperationCancelled(str(exc)) from exc
            raise

        final_output_dir = (resolved_output or (resolved_input / "PRORES")).resolve()
        return {
            "input_dir": str(resolved_input),
            "output_dir": str(final_output_dir),
            "count": len(outputs),
            "outputs": [str(Path(p).resolve()) for p in outputs],
            "total_sequences": total_sequences,
        }

    return _start_async_operation(
        kind="dpx_to_prores",
        metadata={
            "input_dir": str(resolved_input),
            "output_dir": str(resolved_output) if resolved_output else None,
            "framerate": int(framerate),
            "overwrite": bool(overwrite),
        },
        cancellable=True,
        runner=_runner,
    )


def get_operation(operation_id: str) -> OperationSnapshot | None:
    return _OPERATIONS.get(operation_id)


def list_operations(limit: int = 100) -> tuple[OperationSnapshot, ...]:
    return _OPERATIONS.list(limit=limit)


def poll_operation_events(
    *,
    after_seq: int = 0,
    operation_id: str | None = None,
    limit: int = 200,
) -> tuple[OperationEvent, ...]:
    return _OPERATIONS.poll_events(after_seq=after_seq, operation_id=operation_id, limit=limit)


def wait_for_operation(operation_id: str, timeout_seconds: float | None = None) -> OperationSnapshot | None:
    return _OPERATIONS.wait(operation_id, timeout_seconds=timeout_seconds)


def cancel_operation(operation_id: str) -> bool:
    return _OPERATIONS.request_cancel(operation_id)
