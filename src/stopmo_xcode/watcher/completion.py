from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import time


@dataclass
class Snapshot:
    size: int
    mtime: float
    last_change_monotonic: float


class FileCompletionTracker:
    """Detects when files are stable and likely fully written."""

    def __init__(self, stable_seconds: float) -> None:
        self.stable_seconds = stable_seconds
        self._snapshots: dict[Path, Snapshot] = {}
        self._already_ready: set[Path] = set()

    def mark_candidate(self, path: Path) -> None:
        if path in self._already_ready:
            return
        try:
            st = path.stat()
        except FileNotFoundError:
            return

        now = time.monotonic()
        prev = self._snapshots.get(path)
        if prev is None:
            self._snapshots[path] = Snapshot(size=st.st_size, mtime=st.st_mtime, last_change_monotonic=now)
            return

        if st.st_size != prev.size or st.st_mtime != prev.mtime:
            self._snapshots[path] = Snapshot(size=st.st_size, mtime=st.st_mtime, last_change_monotonic=now)

    def collect_ready(self) -> list[Path]:
        now = time.monotonic()
        ready: list[Path] = []
        for path, snap in list(self._snapshots.items()):
            try:
                st = path.stat()
            except FileNotFoundError:
                del self._snapshots[path]
                continue

            if st.st_size != snap.size or st.st_mtime != snap.mtime:
                self._snapshots[path] = Snapshot(size=st.st_size, mtime=st.st_mtime, last_change_monotonic=now)
                continue

            age_since_change = now - snap.last_change_monotonic
            age_since_mtime = time.time() - st.st_mtime
            if age_since_change >= self.stable_seconds and age_since_mtime >= self.stable_seconds:
                ready.append(path)
                self._already_ready.add(path)
                del self._snapshots[path]

        return ready
