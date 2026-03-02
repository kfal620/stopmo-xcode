from __future__ import annotations

from pathlib import Path
import time

from stopmo_xcode.watcher.completion import FileCompletionTracker


def test_completion_tracker_marks_file_ready(tmp_path: Path) -> None:
    tracker = FileCompletionTracker(stable_seconds=0.05)
    path = tmp_path / "frame.CR3"
    path.write_bytes(b"abc")

    tracker.mark_candidate(path)
    assert tracker.collect_ready() == []

    time.sleep(0.07)
    ready = tracker.collect_ready()
    assert ready == [path]

    # Should not emit same path again once marked ready.
    tracker.mark_candidate(path)
    assert tracker.collect_ready() == []


def test_completion_tracker_rearms_ready_file_when_callback_requests(tmp_path: Path) -> None:
    rearm = {"value": False}
    tracker = FileCompletionTracker(
        stable_seconds=0.05,
        should_rearm_ready_file=lambda _path: bool(rearm["value"]),
    )
    path = tmp_path / "frame.CR3"
    path.write_bytes(b"abc")

    tracker.mark_candidate(path)
    time.sleep(0.07)
    assert tracker.collect_ready() == [path]

    tracker.mark_candidate(path)
    assert tracker.collect_ready() == []

    rearm["value"] = True
    tracker.mark_candidate(path)
    assert tracker.collect_ready() == []
    time.sleep(0.07)
    assert tracker.collect_ready() == [path]


def test_completion_tracker_rearms_after_path_disappears_from_scan(tmp_path: Path) -> None:
    tracker = FileCompletionTracker(stable_seconds=0.05)
    path = tmp_path / "frame.CR3"
    path.write_bytes(b"abc")

    tracker.mark_candidate(path)
    time.sleep(0.07)
    assert tracker.collect_ready() == [path]

    path.unlink()
    tracker.reconcile_observed_candidates(set())

    path.write_bytes(b"abc")
    tracker.mark_candidate(path)
    time.sleep(0.07)
    assert tracker.collect_ready() == [path]
