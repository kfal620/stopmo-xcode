"""Manifest and per-frame sidecar serialization helpers."""

from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any


@dataclass
class ShotManifest:
    """Shot-level provenance record that captures the locked settings behind a DPX sequence."""

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
    """Per-frame provenance record that links each DPX file back to source metadata and hashes."""

    shot_name: str
    frame_number: int
    source_filename: str
    source_sha256: str
    dpx_filename: str
    metadata: dict[str, Any]


def utc_now_iso() -> str:
    """Use one UTC timestamp format across manifest and frame-record provenance files."""

    return datetime.now(timezone.utc).isoformat()


def write_shot_manifest(path: Path, manifest: ShotManifest) -> None:
    """Persist shot provenance in a stable JSON layout so diffs and support bundles stay readable."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(manifest), f, indent=2, sort_keys=True)
        f.write("\n")


def write_frame_record(path: Path, record: FrameRecord) -> None:
    """Persist per-frame provenance in a stable JSON layout for debugging and audit trails."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(asdict(record), f, indent=2, sort_keys=True)
        f.write("\n")
