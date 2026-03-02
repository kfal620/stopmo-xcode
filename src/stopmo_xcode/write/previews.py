"""Shot preview JPEG generation helpers for lightweight GUI thumbnails."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
import json
import math
from pathlib import Path
import time
from typing import Any

import numpy as np

PREVIEW_MAX_EDGE = 960
PREVIEW_JPEG_QUALITY = 78
PREVIEW_LATEST_THROTTLE_SECONDS = 1.0
PREVIEW_RENDER_INTENT = "logc_awg"


def _utc_now_iso() -> str:
    """Return UTC timestamp string used by preview sidecar metadata."""

    return datetime.now(timezone.utc).isoformat()


def _read_json(path: Path) -> dict[str, Any]:
    """Best-effort JSON object read for preview sidecars."""

    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _atomic_write_bytes(path: Path, payload: bytes) -> None:
    """Atomically replace a file payload to avoid partially-written JPEGs."""

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_bytes(payload)
    tmp_path.replace(path)


def _atomic_write_json(path: Path, payload: dict[str, object]) -> None:
    """Atomically write JSON sidecar payload with stable formatting."""

    _atomic_write_bytes(path, (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def _best_effort_remove(path: Path) -> None:
    """Best-effort unlink for stale alternate preview variants."""

    try:
        if path.exists():
            path.unlink()
    except Exception:
        # Preview cleanup is non-critical and must never fail a frame job.
        pass


def _downsample_logc_for_preview(logc: np.ndarray, max_edge: int) -> np.ndarray:
    """Downsample logc input via integer stepping to reduce preview compute cost."""

    if logc.ndim != 3 or logc.shape[2] < 3:
        raise ValueError("logc preview input must be HxWx3 array")
    h, w = int(logc.shape[0]), int(logc.shape[1])
    edge = max(h, w)
    if edge <= max(1, int(max_edge)):
        return logc[:, :, :3]
    step = max(1, int(math.ceil(float(edge) / float(max_edge))))
    return logc[::step, ::step, :3]


def _preview_rgb8_from_logc(logc: np.ndarray, max_edge: int) -> np.ndarray:
    """Convert LogC3/AWG frame data into compact 8-bit signal-space preview pixels."""

    sampled = _downsample_logc_for_preview(logc, max_edge=max_edge)
    signal = np.clip(sampled, 0.0, 1.0)
    return np.rint(signal * 255.0).astype(np.uint8)


def _encode_preview_jpeg(logc: np.ndarray, *, max_edge: int, quality: int) -> bytes | None:
    """Encode preview JPEG bytes, returning None when PIL is unavailable."""

    try:
        from PIL import Image
    except Exception:
        return None

    rgb8 = _preview_rgb8_from_logc(logc, max_edge=max_edge)
    with BytesIO() as buf:
        Image.fromarray(rgb8, mode="RGB").save(
            buf,
            format="JPEG",
            quality=max(1, min(95, int(quality))),
            optimize=False,
            progressive=False,
        )
        return buf.getvalue()


def _encode_preview_tiff(logc: np.ndarray, *, max_edge: int) -> bytes | None:
    """Encode preview TIFF bytes, returning None when tifffile is unavailable."""

    try:
        import tifffile  # type: ignore
    except Exception:
        return None

    rgb8 = _preview_rgb8_from_logc(logc, max_edge=max_edge)
    with BytesIO() as buf:
        tifffile.imwrite(buf, rgb8, photometric="rgb")
        return buf.getvalue()


@dataclass(frozen=True)
class PreviewWriteStatus:
    """Status response for preview generation attempts."""

    path: Path | None
    wrote: bool
    skipped: bool
    reason: str | None = None


def write_latest_preview(
    *,
    shot_dir: Path,
    source_stem: str,
    logc: np.ndarray,
    max_edge: int = PREVIEW_MAX_EDGE,
    quality: int = PREVIEW_JPEG_QUALITY,
    throttle_seconds: float = PREVIEW_LATEST_THROTTLE_SECONDS,
) -> PreviewWriteStatus:
    """Write/update the per-shot latest preview JPEG with mtime throttling."""

    preview_dir = shot_dir / "preview"
    jpg_path = preview_dir / "latest.jpg"
    tiff_path = preview_dir / "latest.tiff"
    meta_path = preview_dir / "latest.meta.json"

    existing_meta = _read_json(meta_path)
    requires_intent_refresh = existing_meta.get("render_intent") != PREVIEW_RENDER_INTENT
    existing_preview = jpg_path if jpg_path.exists() else tiff_path if tiff_path.exists() else None
    if throttle_seconds > 0 and existing_preview is not None and not requires_intent_refresh:
        age = max(0.0, time.time() - float(existing_preview.stat().st_mtime))
        if age < float(throttle_seconds):
            return PreviewWriteStatus(path=existing_preview, wrote=False, skipped=True, reason="throttled")

    payload = _encode_preview_jpeg(logc, max_edge=max_edge, quality=quality)
    target_path = jpg_path
    alt_path = tiff_path
    if payload is None:
        payload = _encode_preview_tiff(logc, max_edge=max_edge)
        target_path = tiff_path
        alt_path = jpg_path
    if payload is None:
        return PreviewWriteStatus(path=None, wrote=False, skipped=True, reason="encoder_unavailable")

    _atomic_write_bytes(target_path, payload)
    _best_effort_remove(alt_path)
    _atomic_write_json(
        meta_path,
        {
            "updated_at_utc": _utc_now_iso(),
            "source_stem": source_stem,
            "max_edge": int(max_edge),
            "jpeg_quality": int(quality),
            "render_intent": PREVIEW_RENDER_INTENT,
        },
    )
    return PreviewWriteStatus(path=target_path, wrote=True, skipped=False, reason=None)


def update_first_preview_if_earlier(
    *,
    shot_dir: Path,
    frame_number: int,
    source_stem: str,
    logc: np.ndarray,
    max_edge: int = PREVIEW_MAX_EDGE,
    quality: int = PREVIEW_JPEG_QUALITY,
) -> PreviewWriteStatus:
    """Write first preview JPEG only when no first exists or frame number is earlier."""

    preview_dir = shot_dir / "preview"
    jpg_path = preview_dir / "first.jpg"
    tiff_path = preview_dir / "first.tiff"
    meta_path = preview_dir / "first.meta.json"

    existing_meta = _read_json(meta_path)
    requires_intent_refresh = existing_meta.get("render_intent") != PREVIEW_RENDER_INTENT
    existing_frame = existing_meta.get("frame_number")
    current = int(frame_number)
    existing_preview = jpg_path if jpg_path.exists() else tiff_path if tiff_path.exists() else None
    if (
        existing_preview is not None
        and isinstance(existing_frame, int)
        and current >= existing_frame
        and not requires_intent_refresh
    ):
        return PreviewWriteStatus(path=existing_preview, wrote=False, skipped=True, reason="not_earlier")

    payload = _encode_preview_jpeg(logc, max_edge=max_edge, quality=quality)
    target_path = jpg_path
    alt_path = tiff_path
    if payload is None:
        payload = _encode_preview_tiff(logc, max_edge=max_edge)
        target_path = tiff_path
        alt_path = jpg_path
    if payload is None:
        return PreviewWriteStatus(path=None, wrote=False, skipped=True, reason="encoder_unavailable")

    _atomic_write_bytes(target_path, payload)
    _best_effort_remove(alt_path)
    _atomic_write_json(
        meta_path,
        {
            "frame_number": current,
            "updated_at_utc": _utc_now_iso(),
            "source_stem": source_stem,
            "max_edge": int(max_edge),
            "jpeg_quality": int(quality),
            "render_intent": PREVIEW_RENDER_INTENT,
        },
    )
    return PreviewWriteStatus(path=target_path, wrote=True, skipped=False, reason=None)
