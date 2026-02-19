from __future__ import annotations

from pathlib import Path

from stopmo_xcode import app_api
from stopmo_xcode.config import load_config
from stopmo_xcode.gui_bridge import (
    copy_diagnostics_bundle_payload,
    dpx_to_prores_payload,
    health_payload,
    history_summary_payload,
    logs_diagnostics_payload,
    queue_status_payload,
    read_config_payload,
    suggest_matrix_payload,
    shots_summary_payload,
    transcode_one_payload,
    validate_config_payload,
    watch_start_payload,
    watch_state_payload,
    watch_preflight_payload,
    write_config_payload,
)
from stopmo_xcode.queue import QueueDB


def _write_min_config(tmp_path: Path) -> Path:
    cfg_file = tmp_path / "config.yaml"
    cfg_file.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
""",
        encoding="utf-8",
    )
    return cfg_file


def test_read_config_payload_has_expected_sections(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    payload = read_config_payload(cfg_file)
    assert "watch" in payload
    assert "pipeline" in payload
    assert "output" in payload
    assert payload["config_path"] == str(cfg_file.resolve())


def test_write_config_payload_roundtrip(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    payload = read_config_payload(cfg_file)
    watch = payload["watch"]
    assert isinstance(watch, dict)
    watch["max_workers"] = 4
    payload["log_level"] = "DEBUG"

    out = write_config_payload(cfg_file, payload)
    assert out["saved"] is True

    reloaded = load_config(cfg_file)
    assert reloaded.watch.max_workers == 4
    assert reloaded.log_level == "DEBUG"


def test_health_payload_reports_core_keys(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    payload = health_payload(cfg_file)
    assert "checks" in payload
    checks = payload["checks"]
    assert isinstance(checks, dict)
    assert "rawpy" in checks
    assert "ffmpeg" in checks
    assert payload["config_exists"] is True


def test_queue_status_payload_reports_counts_and_recent(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    cfg = load_config(cfg_file)
    db = QueueDB(cfg.watch.db_path)
    try:
        src_a = cfg.watch.source_dir / "SHOT_A_0001.CR3"
        src_b = cfg.watch.source_dir / "SHOT_A_0002.CR3"
        src_c = cfg.watch.source_dir / "SHOT_B_0001.CR3"
        src_a.write_bytes(b"a")
        src_b.write_bytes(b"b")
        src_c.write_bytes(b"c")

        assert db.enqueue_detected(src_a, shot_name="SHOT_A", frame_number=1)
        job = db.lease_next_job(worker_id="w1")
        assert job is not None
        db.mark_done(job.id, output_path=cfg.watch.output_dir / "SHOT_A" / "dpx" / "SHOT_A_0001.dpx")

        assert db.enqueue_detected(src_b, shot_name="SHOT_A", frame_number=2)
        job2 = db.lease_next_job(worker_id="w2")
        assert job2 is not None
        db.mark_failed(job2.id, error="decode failed")

        assert db.enqueue_detected(src_c, shot_name="SHOT_B", frame_number=1)
    finally:
        db.close()

    payload = queue_status_payload(cfg_file, limit=10)
    counts = payload["counts"]
    assert isinstance(counts, dict)
    assert counts.get("done") == 1
    assert counts.get("failed") == 1
    assert counts.get("detected") == 1

    recent = payload["recent"]
    assert isinstance(recent, list)
    assert len(recent) == 3


def test_shots_summary_payload_groups_by_shot(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    cfg = load_config(cfg_file)
    db = QueueDB(cfg.watch.db_path)
    try:
        src_a1 = cfg.watch.source_dir / "SHOT_A_0001.CR3"
        src_a2 = cfg.watch.source_dir / "SHOT_A_0002.CR3"
        src_b1 = cfg.watch.source_dir / "SHOT_B_0001.CR3"
        src_a1.write_bytes(b"a")
        src_a2.write_bytes(b"b")
        src_b1.write_bytes(b"c")

        assert db.enqueue_detected(src_a1, shot_name="SHOT_A", frame_number=1)
        leased = db.lease_next_job(worker_id="w1")
        assert leased is not None
        db.mark_done(leased.id, output_path=cfg.watch.output_dir / "SHOT_A" / "dpx" / "SHOT_A_0001.dpx")

        assert db.enqueue_detected(src_a2, shot_name="SHOT_A", frame_number=2)
        leased2 = db.lease_next_job(worker_id="w2")
        assert leased2 is not None
        db.mark_failed(leased2.id, error="fail")

        assert db.enqueue_detected(src_b1, shot_name="SHOT_B", frame_number=1)
    finally:
        db.close()

    payload = shots_summary_payload(cfg_file, limit=10)
    shots = payload["shots"]
    assert isinstance(shots, list)
    assert len(shots) == 2
    by_name = {row["shot_name"]: row for row in shots}
    assert by_name["SHOT_A"]["total_frames"] == 2
    assert by_name["SHOT_A"]["done_frames"] == 1
    assert by_name["SHOT_A"]["failed_frames"] == 1
    assert by_name["SHOT_B"]["total_frames"] == 1
    assert by_name["SHOT_B"]["inflight_frames"] == 1


def test_watch_state_payload_without_running_service(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    cfg = load_config(cfg_file)
    runtime_state = cfg.watch.working_dir / ".stopmo_runtime_state.json"
    runtime_state.parent.mkdir(parents=True, exist_ok=True)
    runtime_state.write_text(
        """
{
  "last_startup_utc": "2026-01-01T00:00:00+00:00",
  "last_shutdown_utc": "2026-01-01T00:10:00+00:00",
  "last_inflight_reset_count": 3,
  "running": false
}
""".strip()
        + "\n",
        encoding="utf-8",
    )
    payload = watch_state_payload(cfg_file, queue_limit=20, log_tail_lines=5)
    assert payload["running"] is False
    assert payload["pid"] is None
    assert payload["queue"] is not None
    crash = payload["crash_recovery"]
    assert crash["last_inflight_reset_count"] == 3


def test_transcode_one_payload_wraps_operation(monkeypatch, tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    frame = tmp_path / "incoming" / "SHOT_A_0001.CR3"
    frame.parent.mkdir(parents=True, exist_ok=True)
    frame.write_bytes(b"x")

    op_snapshot = app_api.OperationSnapshot(
        id="op_1",
        kind="transcode_one",
        status="succeeded",
        progress=1.0,
        created_at_utc="2026-01-01T00:00:00+00:00",
        started_at_utc="2026-01-01T00:00:01+00:00",
        finished_at_utc="2026-01-01T00:00:02+00:00",
        cancel_requested=False,
        cancellable=False,
        error=None,
        metadata={},
        result={"output_path": "/tmp/out.dpx"},
    )
    ev = app_api.OperationEvent(
        seq=1,
        operation_id="op_1",
        timestamp_utc="2026-01-01T00:00:00+00:00",
        event_type="operation_succeeded",
        message=None,
        payload={"output_path": "/tmp/out.dpx"},
    )

    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.start_transcode_one_operation", lambda **kwargs: "op_1")
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.wait_for_operation", lambda op_id, timeout_seconds=None: op_snapshot)
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.poll_operation_events", lambda **kwargs: (ev,))

    payload = transcode_one_payload(cfg_file, frame, None)
    assert payload["operation_id"] == "op_1"
    assert payload["operation"]["status"] == "succeeded"
    assert len(payload["events"]) == 1


def test_suggest_matrix_payload_wraps_operation(monkeypatch, tmp_path: Path) -> None:
    frame = tmp_path / "frame.CR3"
    frame.write_bytes(b"x")

    op_snapshot = app_api.OperationSnapshot(
        id="op_2",
        kind="suggest_matrix",
        status="succeeded",
        progress=1.0,
        created_at_utc="2026-01-01T00:00:00+00:00",
        started_at_utc="2026-01-01T00:00:01+00:00",
        finished_at_utc="2026-01-01T00:00:02+00:00",
        cancel_requested=False,
        cancellable=False,
        error=None,
        metadata={},
        result={"camera_to_reference_matrix": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]},
    )

    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.start_suggest_matrix_operation", lambda **kwargs: "op_2")
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.wait_for_operation", lambda op_id, timeout_seconds=None: op_snapshot)
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.poll_operation_events", lambda **kwargs: ())

    payload = suggest_matrix_payload(frame, "Canon", "EOS R", None)
    assert payload["operation_id"] == "op_2"
    assert payload["operation"]["kind"] == "suggest_matrix"


def test_dpx_to_prores_payload_wraps_operation(monkeypatch, tmp_path: Path) -> None:
    inp = tmp_path / "out"
    inp.mkdir(parents=True, exist_ok=True)
    op_snapshot = app_api.OperationSnapshot(
        id="op_3",
        kind="dpx_to_prores",
        status="succeeded",
        progress=1.0,
        created_at_utc="2026-01-01T00:00:00+00:00",
        started_at_utc="2026-01-01T00:00:01+00:00",
        finished_at_utc="2026-01-01T00:00:02+00:00",
        cancel_requested=False,
        cancellable=True,
        error=None,
        metadata={},
        result={"count": 2},
    )

    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.start_dpx_to_prores_operation", lambda **kwargs: "op_3")
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.wait_for_operation", lambda op_id, timeout_seconds=None: op_snapshot)
    monkeypatch.setattr("stopmo_xcode.gui_bridge.app_api.poll_operation_events", lambda **kwargs: ())

    payload = dpx_to_prores_payload(inp, None, 24, True)
    assert payload["operation_id"] == "op_3"
    assert payload["operation"]["kind"] == "dpx_to_prores"


def test_logs_diagnostics_payload_parses_warnings(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    cfg = load_config(cfg_file)
    log_path = cfg.watch.working_dir / "watch-service.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        "\n".join(
            [
                "2026-02-19 10:00:00,000 WARNING stopmo_xcode.worker high pre-log clipping ratio 2.00% in x.CR3",
                "2026-02-19 10:00:01,000 WARNING stopmo_xcode.worker non-finite values detected in decoded frame: y.CR3",
                "2026-02-19 10:00:02,000 ERROR stopmo_xcode.worker decode failed for job=1",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    payload = logs_diagnostics_payload(cfg_file, severity=None, limit=50)
    entries = payload["entries"]
    warnings = payload["warnings"]
    assert isinstance(entries, list)
    assert isinstance(warnings, list)
    assert len(entries) == 3
    codes = {row["code"] for row in warnings}
    assert "clipping" in codes
    assert "nan_inf" in codes
    assert "decode_failure" in codes


def test_history_summary_payload_returns_runs(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    cfg = load_config(cfg_file)
    db = QueueDB(cfg.watch.db_path)
    try:
        src_a = cfg.watch.source_dir / "SHOT_A_0001.CR3"
        src_b = cfg.watch.source_dir / "SHOT_B_0001.CR3"
        src_a.write_bytes(b"a")
        src_b.write_bytes(b"b")
        assert db.enqueue_detected(src_a, shot_name="SHOT_A", frame_number=1)
        job_a = db.lease_next_job(worker_id="w1")
        assert job_a is not None
        db.mark_done(job_a.id, output_path=cfg.watch.output_dir / "SHOT_A" / "dpx" / "SHOT_A_0001.dpx")
        assert db.enqueue_detected(src_b, shot_name="SHOT_B", frame_number=1)
        job_b = db.lease_next_job(worker_id="w2")
        assert job_b is not None
        db.mark_failed(job_b.id, error="decode failed")
    finally:
        db.close()

    payload = history_summary_payload(cfg_file, limit=10, gap_minutes=60)
    assert payload["count"] >= 1
    runs = payload["runs"]
    assert isinstance(runs, list)
    top = runs[0]
    assert int(top["total_jobs"]) >= 2
    assert int(top["failed_jobs"]) >= 1


def test_copy_diagnostics_bundle_payload_writes_file(tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)
    payload = copy_diagnostics_bundle_payload(cfg_file, out_dir=tmp_path / "diag", log_limit=20)
    assert "bundle_path" in payload
    bundle_path = Path(str(payload["bundle_path"]))
    assert bundle_path.exists()


def test_validate_config_payload_flags_invalid_values(tmp_path: Path) -> None:
    cfg_file = tmp_path / "bad.yaml"
    cfg_file.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
  max_workers: 0
  stable_seconds: 0
  shot_regex: "("
output:
  framerate: 0
""",
        encoding="utf-8",
    )
    payload = validate_config_payload(cfg_file)
    assert payload["ok"] is False
    errors = payload["errors"]
    assert isinstance(errors, list)
    fields = {row["field"] for row in errors}
    assert "watch.max_workers" in fields
    assert "watch.stable_seconds" in fields
    assert "watch.shot_regex" in fields
    assert "output.framerate" in fields


def test_watch_preflight_payload_blocks_missing_rawpy(monkeypatch, tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)

    def _fake_health(config_path):
        payload = health_payload(config_path)
        checks = dict(payload["checks"])
        checks["rawpy"] = False
        payload["checks"] = checks
        return payload

    monkeypatch.setattr("stopmo_xcode.gui_bridge.health_payload", _fake_health)
    preflight = watch_preflight_payload(cfg_file)
    assert preflight["ok"] is False
    blockers = preflight["blockers"]
    assert isinstance(blockers, list)
    assert "missing_rawpy" in blockers


def test_watch_start_payload_is_blocked_by_preflight(monkeypatch, tmp_path: Path) -> None:
    cfg_file = _write_min_config(tmp_path)

    monkeypatch.setattr(
        "stopmo_xcode.gui_bridge.watch_preflight_payload",
        lambda config_path: {
            "config_path": str(Path(config_path).resolve()),
            "ok": False,
            "blockers": ["missing_rawpy"],
            "validation": {"ok": True, "errors": [], "warnings": []},
            "health_checks": {"rawpy": False},
        },
    )
    payload = watch_start_payload(cfg_file)
    assert payload["start_blocked"] is True
    assert "launch_error" in payload
