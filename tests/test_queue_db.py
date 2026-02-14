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
