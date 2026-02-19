from __future__ import annotations

import logging
from pathlib import Path
import queue
import threading
import time
from typing import Callable

from .completion import FileCompletionTracker


logger = logging.getLogger(__name__)


class _NoopEventStream:
    def start(self) -> None:
        return None

    def stop(self) -> None:
        return None


class SourceWatcher:
    def __init__(
        self,
        source_dir: Path,
        include_extensions: tuple[str, ...],
        stable_seconds: float,
        poll_interval_seconds: float,
        scan_interval_seconds: float,
        on_ready_file: Callable[[Path], None],
    ) -> None:
        self.source_dir = source_dir
        self.include_extensions = tuple(e.lower() for e in include_extensions)
        self.poll_interval_seconds = poll_interval_seconds
        self.scan_interval_seconds = scan_interval_seconds
        self.on_ready_file = on_ready_file
        self._tracker = FileCompletionTracker(stable_seconds=stable_seconds)
        self._event_queue: queue.Queue[Path] = queue.Queue()
        self._stop_event = threading.Event()
        self._event_stream = _NoopEventStream()

    def stop(self) -> None:
        self._stop_event.set()

    def _is_candidate(self, path: Path) -> bool:
        return path.is_file() and path.suffix.lower() in self.include_extensions

    def _scan_tree(self) -> None:
        for path in self.source_dir.rglob("*"):
            if self._is_candidate(path):
                self._tracker.mark_candidate(path)

    def run_forever(self, external_stop_event: threading.Event | None = None) -> None:
        logger.info("watching source directory: %s", self.source_dir)
        last_scan = 0.0
        while not self._stop_event.is_set():
            if external_stop_event is not None and external_stop_event.is_set():
                break

            now = time.monotonic()
            if now - last_scan >= self.scan_interval_seconds:
                self._scan_tree()
                last_scan = now

            while True:
                try:
                    path = self._event_queue.get_nowait()
                except queue.Empty:
                    break
                if self._is_candidate(path):
                    self._tracker.mark_candidate(path)

            ready = self._tracker.collect_ready()
            for path in ready:
                self.on_ready_file(path)

            time.sleep(self.poll_interval_seconds)

    def poll_once(self) -> list[Path]:
        self._scan_tree()
        return self._tracker.collect_ready()
