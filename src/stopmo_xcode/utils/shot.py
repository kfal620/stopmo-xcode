from __future__ import annotations

from pathlib import Path
import re


_FRAME_RE = re.compile(r"(\d+)(?!.*\d)")


def infer_shot_name(path: Path, shot_regex: str | None = None) -> str:
    if shot_regex:
        m = re.search(shot_regex, str(path))
        if m:
            return m.group(1) if m.groups() else m.group(0)
    return path.parent.name or "default_shot"


def infer_frame_number(path: Path) -> int:
    m = _FRAME_RE.search(path.stem)
    if m:
        return int(m.group(1))
    return 0
