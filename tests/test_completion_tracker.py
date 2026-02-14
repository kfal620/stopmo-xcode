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
