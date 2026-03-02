"""File stability tracker used to detect when incoming files are fully written."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import time
from typing import Callable


@dataclass
class Snapshot:
    """Observed file state snapshot used for readiness decisions."""

    size: int
    mtime: float
    last_change_monotonic: float


class FileCompletionTracker:
    """Detects when files are stable and likely fully written."""

    def __init__(
        self,
        stable_seconds: float,
        should_rearm_ready_file: Callable[[Path], bool] | None = None,
    ) -> None:
        self.stable_seconds = stable_seconds
        self._snapshots: dict[Path, Snapshot] = {}
        self._already_ready: dict[Path, tuple[int, float]] = {}
        self._should_rearm_ready_file = should_rearm_ready_file

    def reconcile_observed_candidates(self, observed_paths: set[Path]) -> None:
        """Drop stale tracker state for files that disappeared from the latest scan."""

        for path in list(self._snapshots):
            if path not in observed_paths:
                del self._snapshots[path]
        for path in list(self._already_ready):
            if path not in observed_paths:
                del self._already_ready[path]

    def mark_candidate(self, path: Path) -> None:
        try:
            st = path.stat()
        except FileNotFoundError:
            self._snapshots.pop(path, None)
            self._already_ready.pop(path, None)
            return

        now = time.monotonic()
        if path in self._already_ready:
            ready_size, ready_mtime = self._already_ready[path]
            signature_changed = st.st_size != ready_size or st.st_mtime != ready_mtime
            should_rearm = False
            if not signature_changed and self._should_rearm_ready_file is not None:
                should_rearm = bool(self._should_rearm_ready_file(path))
            if signature_changed or should_rearm:
                del self._already_ready[path]
                self._snapshots[path] = Snapshot(size=st.st_size, mtime=st.st_mtime, last_change_monotonic=now)
            return

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
                self._already_ready[path] = (st.st_size, st.st_mtime)
                del self._snapshots[path]

        return ready
