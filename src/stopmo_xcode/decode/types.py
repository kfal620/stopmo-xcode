from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class RawMetadata:
    source_path: Path
    wb_multipliers: tuple[float, float, float, float]
    as_shot_wb_multipliers: tuple[float, float, float, float] | None
    black_level_per_channel: tuple[int, int, int, int] | None
    white_level: int | None
    cfa_pattern: str | None
    iso: float | None
    shutter_s: float | None
    aperture_f: float | None


@dataclass
class DecodedFrame:
    linear_camera_rgb: np.ndarray
    metadata: RawMetadata
