from __future__ import annotations

from pathlib import Path

from stopmo_xcode.queue import JobState, QueueDB


def test_queue_crash_resume(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")

    src = tmp_path / "A_0001.CR3"
    src.write_bytes(b"x")

    assert db.enqueue_detected(src, shot_name="SHOT_A", frame_number=1)
    job = db.lease_next_job(worker_id="w1")
    assert job is not None
    assert job.state == JobState.DECODING.value

    reset = db.reset_inflight_to_detected()
    assert reset == 1

    leased_again = db.lease_next_job(worker_id="w2")
    assert leased_again is not None
    assert leased_again.id == job.id

    db.close()


def test_shot_settings_roundtrip(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src = tmp_path / "A_0001.CR3"
    src.write_bytes(b"x")

    db.set_shot_settings(
        shot_name="SHOT_A",
        wb_multipliers=(2.0, 1.0, 1.8, 1.0),
        exposure_offset_stops=0.0,
        reference_source_path=src,
    )

    settings = db.get_shot_settings("SHOT_A")
    assert settings is not None
    assert settings.wb_multipliers == (2.0, 1.0, 1.8, 1.0)
    db.close()


def test_retry_failed_for_shot_only_resets_failed_rows(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src1 = tmp_path / "A_0001.CR3"
    src2 = tmp_path / "A_0002.CR3"
    src3 = tmp_path / "A_0003.CR3"
    src1.write_bytes(b"1")
    src2.write_bytes(b"2")
    src3.write_bytes(b"3")
    assert db.enqueue_detected(src1, shot_name="SHOT_A", frame_number=1)
    assert db.enqueue_detected(src2, shot_name="SHOT_A", frame_number=2)
    assert db.enqueue_detected(src3, shot_name="SHOT_A", frame_number=3)

    leased1 = db.lease_job_for_source(src1, worker_id="w1")
    leased2 = db.lease_job_for_source(src2, worker_id="w1")
    leased3 = db.lease_job_for_source(src3, worker_id="w1")
    assert leased1 and leased2 and leased3
    db.mark_failed(leased1.id, "boom")
    db.mark_done(leased2.id, output_path=tmp_path / "out2.dpx")
    db.mark_failed(leased3.id, "boom-2")

    changed = db.retry_failed_for_shot("SHOT_A")
    assert changed == 2

    counts = db.shot_state_counts("SHOT_A")
    assert counts["failed"] == 0
    assert counts[JobState.DETECTED.value] == 2
    assert counts[JobState.DONE.value] == 1
    db.close()


def test_restart_shot_resets_jobs_and_clears_locks_and_assembly(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src1 = tmp_path / "B_0001.CR3"
    src2 = tmp_path / "B_0002.CR3"
    src1.write_bytes(b"1")
    src2.write_bytes(b"2")
    assert db.enqueue_detected(src1, shot_name="SHOT_B", frame_number=1)
    assert db.enqueue_detected(src2, shot_name="SHOT_B", frame_number=2)
    leased1 = db.lease_job_for_source(src1, worker_id="w1")
    leased2 = db.lease_job_for_source(src2, worker_id="w1")
    assert leased1 and leased2
    db.mark_done(leased1.id, output_path=tmp_path / "out1.dpx", source_sha256="abc")
    db.mark_failed(leased2.id, "bad")
    db.set_shot_settings(
        shot_name="SHOT_B",
        wb_multipliers=(2.0, 1.0, 1.2, 1.0),
        exposure_offset_stops=0.0,
        reference_source_path=src1,
    )
    db.mark_shot_frame_done("SHOT_B")

    result = db.restart_shot("SHOT_B", reset_locks=True)
    assert result["jobs_changed"] == 2
    assert result["settings_cleared"] is True
    assert result["assembly_cleared"] is True

    counts = db.shot_state_counts("SHOT_B")
    assert counts[JobState.DETECTED.value] == 2
    assert counts["failed"] == 0
    assert db.get_shot_settings("SHOT_B") is None
    db.close()


def test_restart_shot_blocks_when_inflight_exists(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src = tmp_path / "C_0001.CR3"
    src.write_bytes(b"1")
    assert db.enqueue_detected(src, shot_name="SHOT_C", frame_number=1)
    leased = db.lease_job_for_source(src, worker_id="w1")
    assert leased is not None
    try:
        db.restart_shot("SHOT_C", reset_locks=True)
        assert False, "expected restart to fail for inflight shot"
    except ValueError as exc:
        assert "inflight" in str(exc)
    db.close()


def test_delete_shot_removes_rows_and_blocks_inflight(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src1 = tmp_path / "D_0001.CR3"
    src2 = tmp_path / "E_0001.CR3"
    src1.write_bytes(b"1")
    src2.write_bytes(b"2")
    assert db.enqueue_detected(src1, shot_name="SHOT_D", frame_number=1)
    assert db.enqueue_detected(src2, shot_name="SHOT_E", frame_number=1)
    leased_d = db.lease_job_for_source(src1, worker_id="w1")
    leased_e = db.lease_job_for_source(src2, worker_id="w2")
    assert leased_d and leased_e
    db.mark_failed(leased_d.id, "x")
    # Leave SHOT_E inflight by keeping state in decoding.

    removed = db.delete_shot("SHOT_D")
    assert removed["jobs_deleted"] == 1
    assert db.shot_state_counts("SHOT_D")["total"] == 0

    try:
        db.delete_shot("SHOT_E")
        assert False, "expected delete to fail for inflight shot"
    except ValueError as exc:
        assert "inflight" in str(exc)
    db.close()


def test_has_source_path_reflects_shot_delete(tmp_path: Path) -> None:
    db = QueueDB(tmp_path / "queue.sqlite3")
    src = tmp_path / "F_0001.CR3"
    src.write_bytes(b"1")
    assert db.enqueue_detected(src, shot_name="SHOT_F", frame_number=1)
    assert db.has_source_path(src) is True

    removed = db.delete_shot("SHOT_F")
    assert removed["jobs_deleted"] == 1
    assert db.has_source_path(src) is False
    db.close()
