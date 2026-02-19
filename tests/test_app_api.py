from __future__ import annotations

import json
from pathlib import Path
import time

from stopmo_xcode import app_api
from stopmo_xcode.assemble import DpxSequence
from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB


def _write_min_config(tmp_path: Path) -> Path:
    cfg = tmp_path / "config.yaml"
    cfg.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
""",
        encoding="utf-8",
    )
    return cfg


def test_get_status_returns_typed_payload(tmp_path: Path) -> None:
    cfg_path = _write_min_config(tmp_path)
    cfg = load_config(cfg_path)

    src = cfg.watch.source_dir / "SHOT_A_0001.CR3"
    src.write_bytes(b"x")

    db = QueueDB(cfg.watch.db_path)
    try:
        assert db.enqueue_detected(src, shot_name="SHOT_A", frame_number=1)
    finally:
        db.close()

    status = app_api.get_status(cfg_path, limit=10)
    assert status.db_path == str(cfg.watch.db_path)
    assert status.counts.get("detected") == 1
    assert len(status.recent) == 1
    assert status.recent[0].shot == "SHOT_A"
    assert status.recent[0].frame == 1


def test_suggest_matrix_async_operation_writes_json(monkeypatch, tmp_path: Path) -> None:
    frame = tmp_path / "frame.CR3"
    frame.write_bytes(b"x")
    report_path = tmp_path / "reports" / "matrix.json"

    class _FakeReport:
        camera_make = "Canon"
        camera_model = "EOS R"
        source = "known_camera_table.dcraw"
        confidence = "medium"
        assumptions = ("a",)
        notes = ("n",)
        warnings = ()
        input_path = frame.resolve()

        def to_json_dict(self) -> dict[str, object]:
            return {
                "input_path": str(self.input_path),
                "camera_make": self.camera_make,
                "camera_model": self.camera_model,
                "source": self.source,
                "confidence": self.confidence,
                "reference_space": "ACES2065-1",
                "camera_to_reference_matrix": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
                "assumptions": list(self.assumptions),
                "warnings": list(self.warnings),
                "notes": list(self.notes),
            }

        def to_yaml_block(self) -> str:
            return "pipeline:\n  camera_to_reference_matrix:\n    - [1, 0, 0]\n    - [0, 1, 0]\n    - [0, 0, 1]"

    monkeypatch.setattr(app_api, "suggest_camera_to_reference_matrix", lambda *args, **kwargs: _FakeReport())

    op_id = app_api.start_suggest_matrix_operation(
        input_path=frame,
        camera_make_override="Canon",
        camera_model_override="EOS R",
        write_json_path=report_path,
    )

    snapshot = app_api.wait_for_operation(op_id, timeout_seconds=2.0)
    assert snapshot is not None
    assert snapshot.status == "succeeded"
    assert snapshot.result is not None
    assert snapshot.result["camera_make"] == "Canon"
    assert report_path.exists()

    payload = json.loads(report_path.read_text(encoding="utf-8"))
    assert payload["camera_model"] == "EOS R"

    events = app_api.poll_operation_events(operation_id=op_id, limit=50)
    event_types = [ev.event_type for ev in events]
    assert "operation_started" in event_types
    assert "operation_succeeded" in event_types


def test_watch_operation_can_be_cancelled(monkeypatch, tmp_path: Path) -> None:
    cfg_path = _write_min_config(tmp_path)

    def _fake_run_watch_service(config, shutdown_event=None):
        assert shutdown_event is not None
        while not shutdown_event.is_set():
            time.sleep(0.01)

    def _fake_collect_status(db_path: Path, limit: int = 20) -> app_api.QueueStatus:
        return app_api.QueueStatus(
            db_path=str(db_path),
            counts={"detected": 2, "done": 1},
            recent=(),
        )

    monkeypatch.setattr(app_api, "run_watch_service", _fake_run_watch_service)
    monkeypatch.setattr(app_api, "_collect_status_from_db_path", _fake_collect_status)

    op_id = app_api.start_watch_operation(cfg_path, status_poll_interval_seconds=0.01)
    time.sleep(0.05)
    assert app_api.cancel_operation(op_id) is True

    snapshot = app_api.wait_for_operation(op_id, timeout_seconds=2.0)
    assert snapshot is not None
    assert snapshot.status == "cancelled"
    assert snapshot.cancel_requested is True

    events = app_api.poll_operation_events(operation_id=op_id, limit=100)
    event_types = [ev.event_type for ev in events]
    assert "operation_cancel_requested" in event_types
    assert "operation_cancelled" in event_types


def test_dpx_to_prores_async_emits_sequence_events(monkeypatch, tmp_path: Path) -> None:
    input_dir = tmp_path / "input"
    output_dir = tmp_path / "out"
    input_dir.mkdir(parents=True)

    seq1 = DpxSequence(
        shot_name="SHOT_A",
        dpx_dir=input_dir / "SHOT_A" / "dpx",
        raw_prefix="A_",
        sequence_name="A",
        frame_count=2,
    )
    seq2 = DpxSequence(
        shot_name="SHOT_B",
        dpx_dir=input_dir / "SHOT_B" / "dpx",
        raw_prefix="B_",
        sequence_name="B",
        frame_count=2,
    )

    monkeypatch.setattr(app_api, "discover_dpx_sequences", lambda root: [seq1, seq2])

    def _fake_convert(
        *,
        input_root: Path,
        output_root: Path | None,
        framerate: int,
        overwrite: bool,
        on_sequence_complete=None,
        should_stop=None,
    ) -> list[Path]:
        out_root = output_root or (input_root / "PRORES")
        first = out_root / "A.mov"
        second = out_root / "B.mov"
        if on_sequence_complete is not None:
            on_sequence_complete(seq1, first)
            on_sequence_complete(seq2, second)
        return [first, second]

    monkeypatch.setattr(app_api, "convert_dpx_sequences_to_prores", _fake_convert)

    op_id = app_api.start_dpx_to_prores_operation(
        input_dir=input_dir,
        output_dir=output_dir,
        framerate=24,
        overwrite=True,
    )
    snapshot = app_api.wait_for_operation(op_id, timeout_seconds=2.0)
    assert snapshot is not None
    assert snapshot.status == "succeeded"
    assert snapshot.result is not None
    assert snapshot.result["count"] == 2

    seq_events = [
        ev for ev in app_api.poll_operation_events(operation_id=op_id, limit=100) if ev.event_type == "dpx_sequence_complete"
    ]
    assert len(seq_events) == 2
