from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any


@dataclass
class ShotManifest:
    shot_name: str
    target_ei: int
    output_encoding: str
    output_gamut: str
    locked_wb_multipliers: tuple[float, float, float, float]
    exposure_offset_stops: float
    pipeline_hash: str
    tool_version: str
    created_at_utc: str


@dataclass
class FrameRecord:
    shot_name: str
    frame_number: int
    source_filename: str
    source_sha256: str
    dpx_filename: str
    metadata: dict[str, Any]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_shot_manifest(path: Path, manifest: ShotManifest) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(manifest), f, indent=2, sort_keys=True)
        f.write("\n")


def write_frame_record(path: Path, record: FrameRecord) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(record), f, indent=2, sort_keys=True)
        f.write("\n")
