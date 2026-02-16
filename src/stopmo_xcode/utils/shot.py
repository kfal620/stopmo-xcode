from __future__ import annotations

from pathlib import Path
import re


_FRAME_RE = re.compile(r"(\d+)(?!.*\d)")
_STEM_SHOT_RE = re.compile(r"^(.*?)(?:[_\-.]?(\d+))?$")
_GENERIC_PARENT_NAMES = {"incoming", "source", "sources", "capture", "captures", "frames"}


def infer_shot_name(path: Path, shot_regex: str | None = None) -> str:
    if shot_regex:
        m = re.search(shot_regex, str(path))
        if m:
            return m.group(1) if m.groups() else m.group(0)

    # Prefer deriving shot from filename stem so ingest folder names
    # like "incoming/" do not leak into output folder structure.
    stem = path.stem
    m = _STEM_SHOT_RE.match(stem)
    if m:
        prefix = (m.group(1) or "").rstrip("_-. ")
        if prefix:
            return prefix

    parent_name = path.parent.name.strip()
    if parent_name and parent_name.lower() not in _GENERIC_PARENT_NAMES:
        return parent_name
    return "default_shot"


def infer_frame_number(path: Path) -> int:
    m = _FRAME_RE.search(path.stem)
    if m:
        return int(m.group(1))
    return 0
