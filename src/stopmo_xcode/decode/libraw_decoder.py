from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from .base import DecodeError, MissingDependencyError
from .types import DecodedFrame, RawMetadata


try:
    import rawpy  # type: ignore
except Exception:  # pragma: no cover - dependency is optional
    rawpy = None


def _safe_meta(raw: Any, key: str) -> float | None:
    meta = getattr(raw, "metadata", None)
    if meta is None:
        return None
    value = getattr(meta, key, None)
    if value in (None, 0):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _cfa_pattern(raw: Any) -> str | None:
    pattern = getattr(raw, "raw_pattern", None)
    if pattern is None:
        return None
    try:
        return "".join(str(int(v)) for v in np.array(pattern).flatten())
    except Exception:
        return None


def _normalize_wb(values: Any) -> tuple[float, float, float, float]:
    raw = [float(v) for v in list(values or [1.0, 1.0, 1.0, 1.0])]
    if len(raw) >= 4:
        return (raw[0], raw[1], raw[2], raw[3])
    if len(raw) == 3:
        return (raw[0], raw[1], raw[2], raw[1])
    if len(raw) == 2:
        return (raw[0], raw[1], raw[0], raw[1])
    return (1.0, 1.0, 1.0, 1.0)


class LibRawDecoder:
    """RAW decoder using rawpy (LibRaw backend)."""

    def __init__(self) -> None:
        if rawpy is None:
            raise MissingDependencyError("rawpy is required for CR2/CR3 decode: pip install '.[raw]'")

    def decode(self, path: Path, wb_override: tuple[float, float, float, float] | None = None) -> DecodedFrame:
        try:
            with rawpy.imread(str(path)) as raw:
                as_shot_wb = _normalize_wb(raw.camera_whitebalance)
                wb = _normalize_wb(wb_override) if wb_override else as_shot_wb
                rgb = raw.postprocess(
                    output_color=rawpy.ColorSpace.raw,
                    gamma=(1.0, 1.0),
                    no_auto_bright=True,
                    use_camera_wb=False,
                    user_wb=list(wb),
                    output_bps=16,
                    demosaic_algorithm=rawpy.DemosaicAlgorithm.AHD,
                    four_color_rgb=False,
                    highlight_mode=rawpy.HighlightMode.Clip,
                )
                linear = np.asarray(rgb, dtype=np.float32) / 65535.0

                if linear.ndim != 3 or linear.shape[2] < 3:
                    raise DecodeError(f"unexpected decoded shape for {path}: {linear.shape}")

                linear = linear[..., :3]

                black = getattr(raw, "black_level_per_channel", None)
                black_tuple = None
                if black is not None:
                    black_tuple = tuple(int(v) for v in list(black)[:4])
                    if len(black_tuple) == 3:
                        black_tuple = (black_tuple[0], black_tuple[1], black_tuple[2], black_tuple[1])

                white_level = getattr(raw, "white_level", None)
                white_i = int(white_level) if white_level is not None else None

                metadata = RawMetadata(
                    source_path=path,
                    wb_multipliers=wb,
                    as_shot_wb_multipliers=(
                        float(as_shot_wb[0]),
                        float(as_shot_wb[1]),
                        float(as_shot_wb[2]),
                        float(as_shot_wb[3]),
                    ),
                    black_level_per_channel=black_tuple,
                    white_level=white_i,
                    cfa_pattern=_cfa_pattern(raw),
                    iso=_safe_meta(raw, "iso_speed"),
                    shutter_s=_safe_meta(raw, "shutter"),
                    aperture_f=_safe_meta(raw, "aperture"),
                )

                return DecodedFrame(linear_camera_rgb=linear, metadata=metadata)
        except MissingDependencyError:
            raise
        except Exception as exc:
            raise DecodeError(f"decode failed for {path}: {exc}") from exc
