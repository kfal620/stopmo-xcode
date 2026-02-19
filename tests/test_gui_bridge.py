from __future__ import annotations

from pathlib import Path

from stopmo_xcode.config import load_config
from stopmo_xcode.gui_bridge import (
    health_payload,
    queue_status_payload,
    read_config_payload,
    shots_summary_payload,
    watch_state_payload,
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
    payload = watch_state_payload(cfg_file, queue_limit=20, log_tail_lines=5)
    assert payload["running"] is False
    assert payload["pid"] is None
    assert payload["queue"] is not None
