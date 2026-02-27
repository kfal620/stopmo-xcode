"""Manifest and per-frame sidecar serialization helpers."""

from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any


@dataclass
class ShotManifest:
    """Shot-level manifest payload persisted beside DPX outputs."""

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
    """Per-frame provenance payload persisted for auditability."""

    shot_name: str
    frame_number: int
    source_filename: str
    source_sha256: str
    dpx_filename: str
    metadata: dict[str, Any]


def utc_now_iso() -> str:
    """Return UTC timestamp string for manifest/record creation metadata."""

    return datetime.now(timezone.utc).isoformat()


def write_shot_manifest(path: Path, manifest: ShotManifest) -> None:
    """Write shot manifest JSON file with stable formatting."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(manifest), f, indent=2, sort_keys=True)
        f.write("\n")


def write_frame_record(path: Path, record: FrameRecord) -> None:
    """Write per-frame record JSON file with stable formatting."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(record), f, indent=2, sort_keys=True)
        f.write("\n")
