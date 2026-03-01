"""Worker pipeline that transforms RAW frames into deterministic LogC3/AWG outputs."""

from __future__ import annotations

from dataclasses import asdict
import logging
import math
from pathlib import Path
from typing import Any
from datetime import datetime, timezone

import numpy as np

from stopmo_xcode import __version__
from stopmo_xcode.color import ColorPipeline, decode_logc3_ei800
from stopmo_xcode.config import AppConfig
from stopmo_xcode.decode import DecodeError, DecoderRegistry, MissingDependencyError
from stopmo_xcode.queue import Job, JobState, QueueDB
from stopmo_xcode.utils.formatting import shutter_seconds_to_fraction
from stopmo_xcode.utils.hash import sha256_file
from stopmo_xcode.write import (
    FrameRecord,
    PREVIEW_JPEG_QUALITY,
    PREVIEW_LATEST_THROTTLE_SECONDS,
    PREVIEW_MAX_EDGE,
    PreviewWriteStatus,
    ShotManifest,
    update_first_preview_if_earlier,
    write_dpx10_logc_awg,
    write_frame_record,
    write_linear_debug_tiff,
    write_latest_preview,
    write_shot_manifest,
)


logger = logging.getLogger(__name__)


def _warn_nan_inf(rgb: np.ndarray, source_path: Path) -> None:
    """Emit warning if decode output contains non-finite pixel values."""

    if not np.isfinite(rgb).all():
        logger.warning("non-finite values detected in decoded frame: %s", source_path)


def _warn_clipping(rgb: np.ndarray, source_path: Path, threshold: float = 0.01) -> None:
    """Emit warning when pre-transform clipping exceeds a coarse threshold."""

    clipped = np.mean(rgb >= 1.0)
    if clipped > threshold:
        logger.warning("high pre-log clipping ratio %.2f%% in %s", clipped * 100.0, source_path)


def _wb_delta(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    """Return max absolute channel delta between two white-balance multiplier sets."""

    av = np.array(a, dtype=np.float32)
    bv = np.array(b, dtype=np.float32)
    return float(np.max(np.abs(av - bv)))


def _iso_compensation_stops(iso: float | None, target_ei: int) -> float | None:
    """Compute deterministic ISO-based exposure compensation term in stops."""

    if iso is None or iso <= 0.0 or target_ei <= 0:
        return None
    return float(math.log2(float(target_ei) / float(iso)))


def _shutter_compensation_stops(frame_shutter_s: float | None, target_shutter_s: float | None) -> float | None:
    """Compute deterministic shutter compensation term in stops."""

    if frame_shutter_s is None or frame_shutter_s <= 0.0:
        return None
    if target_shutter_s is None or target_shutter_s <= 0.0:
        return None
    return float(math.log2(float(target_shutter_s) / float(frame_shutter_s)))


def _aperture_compensation_stops(frame_aperture_f: float | None, target_aperture_f: float | None) -> float | None:
    """Compute deterministic aperture compensation term in stops."""

    if frame_aperture_f is None or frame_aperture_f <= 0.0:
        return None
    if target_aperture_f is None or target_aperture_f <= 0.0:
        return None
    return float(2.0 * math.log2(float(frame_aperture_f) / float(target_aperture_f)))


def _effective_exposure_offset_stops(
    base_offset_stops: float,
    auto_exposure_from_iso: bool,
    target_ei: int,
    frame_iso: float | None,
    auto_exposure_from_shutter: bool,
    target_shutter_s: float | None,
    frame_shutter_s: float | None,
    auto_exposure_from_aperture: bool,
    target_aperture_f: float | None,
    frame_aperture_f: float | None,
    locked_shot_offset_stops: float | None,
) -> tuple[float, tuple[str, ...]]:
    """Resolve effective exposure offset and report missing metadata terms.

    This keeps exposure deterministic: either use explicit shot lock value or use
    formula-based compensation terms enabled in config.
    """

    auto_enabled = bool(auto_exposure_from_iso or auto_exposure_from_shutter or auto_exposure_from_aperture)
    if auto_enabled:
        out = float(base_offset_stops)
        missing: list[str] = []

        if auto_exposure_from_iso:
            iso_stops = _iso_compensation_stops(frame_iso, target_ei)
            if iso_stops is None:
                missing.append("iso")
            else:
                out += float(iso_stops)

        if auto_exposure_from_shutter:
            shutter_stops = _shutter_compensation_stops(frame_shutter_s, target_shutter_s)
            if shutter_stops is None:
                missing.append("shutter_s")
            else:
                out += float(shutter_stops)

        if auto_exposure_from_aperture:
            aperture_stops = _aperture_compensation_stops(frame_aperture_f, target_aperture_f)
            if aperture_stops is None:
                missing.append("aperture_f")
            else:
                out += float(aperture_stops)

        return out, tuple(missing)

    if locked_shot_offset_stops is not None:
        return float(locked_shot_offset_stops), ()

    return float(base_offset_stops), ()


def _write_truth_pack(
    shot_dir: Path,
    source_stem: str,
    logc: np.ndarray,
    dpx_path: Path,
) -> None:
    """Write optional truth-frame QC artifacts beside primary DPX output."""

    truth_dir = shot_dir / "truth_frame"
    truth_dir.mkdir(parents=True, exist_ok=True)

    # Keep a canonical DPX copy for QC.
    truth_dpx = truth_dir / f"{source_stem}_truth_logc_awg.dpx"
    if not truth_dpx.exists():
        truth_dpx.write_bytes(dpx_path.read_bytes())

    # Lightweight Rec709-ish preview for visual checks.
    try:
        from PIL import Image
    except Exception:
        return

    linear = decode_logc3_ei800(logc)
    srgb = np.clip(linear, 0.0, 1.0) ** (1.0 / 2.2)
    out = np.rint(srgb * 255.0).astype(np.uint8)

    preview = truth_dir / f"{source_stem}_preview_rec709ish.png"
    if not preview.exists():
        Image.fromarray(out, mode="RGB").save(preview)


def _metadata_for_frame(meta: Any) -> dict[str, Any]:
    """Serialize decode metadata and normalize shutter formatting for JSON sidecars."""

    data = asdict(meta)
    data["source_path"] = str(meta.source_path)
    data["shutter_s"] = shutter_seconds_to_fraction(meta.shutter_s)
    return data


class JobProcessor:
    """Process queue jobs through decode, xform, write, and sidecar persistence."""

    def __init__(self, config: AppConfig, db: QueueDB) -> None:
        """Initialize decoder and color pipeline dependencies for worker execution."""

        self.config = config
        self.db = db
        self.decoder: DecoderRegistry | None = None
        self._decoder_init_error: Exception | None = None
        try:
            self.decoder = DecoderRegistry()
        except Exception as exc:
            self._decoder_init_error = exc
        self.color = ColorPipeline(config.pipeline)
        self._preview_warning_once: set[str] = set()

    def process_job(self, job: Job) -> None:
        """Process one leased job through canonical queue lifecycle transitions."""

        source_path = Path(job.source_path)
        logger.info("processing job=%s source=%s", job.id, source_path)

        try:
            if self.decoder is None:
                raise RuntimeError(
                    f"decoder initialization failed: {self._decoder_init_error}. "
                    "Install decode dependencies (rawpy/LibRaw) before processing."
                )

            shot_settings = self.db.get_shot_settings(job.shot_name)
            wb_override = None
            if self.config.pipeline.lock_wb_from_first_frame and shot_settings is not None:
                wb_override = shot_settings.wb_multipliers

            decoded = self.decoder.decode(source_path, wb_override=wb_override)

            effective_offset, missing_inputs = _effective_exposure_offset_stops(
                base_offset_stops=float(self.config.pipeline.exposure_offset_stops),
                auto_exposure_from_iso=bool(self.config.pipeline.auto_exposure_from_iso),
                target_ei=int(self.config.pipeline.target_ei),
                frame_iso=decoded.metadata.iso,
                auto_exposure_from_shutter=bool(self.config.pipeline.auto_exposure_from_shutter),
                target_shutter_s=self.config.pipeline.target_shutter_s,
                frame_shutter_s=decoded.metadata.shutter_s,
                auto_exposure_from_aperture=bool(self.config.pipeline.auto_exposure_from_aperture),
                target_aperture_f=self.config.pipeline.target_aperture_f,
                frame_aperture_f=decoded.metadata.aperture_f,
                locked_shot_offset_stops=(
                    float(shot_settings.exposure_offset_stops) if shot_settings is not None else None
                ),
            )
            if missing_inputs:
                logger.warning(
                    "auto exposure metadata compensation missing/invalid for %s fields=%s; using available terms only",
                    source_path.name,
                    ",".join(missing_inputs),
                )

            if self.config.pipeline.lock_wb_from_first_frame and shot_settings is None:
                self.db.set_shot_settings(
                    shot_name=job.shot_name,
                    wb_multipliers=decoded.metadata.wb_multipliers,
                    exposure_offset_stops=effective_offset,
                    reference_source_path=source_path,
                )
                shot_settings = self.db.get_shot_settings(job.shot_name)

            if shot_settings is not None and decoded.metadata.as_shot_wb_multipliers is not None:
                drift = _wb_delta(shot_settings.wb_multipliers, decoded.metadata.as_shot_wb_multipliers)
                if drift > 0.15:
                    logger.warning(
                        "as-shot WB drift detected shot=%s frame=%s delta=%.4f (lock remains active)",
                        job.shot_name,
                        source_path.name,
                        drift,
                    )

            _warn_nan_inf(decoded.linear_camera_rgb, source_path)
            _warn_clipping(decoded.linear_camera_rgb, source_path)

            self.db.transition(job.id, from_state=JobState.DECODING, to_state=JobState.XFORM)

            logc = self.color.transform(decoded.linear_camera_rgb, exposure_offset_stops=effective_offset)

            self.db.transition(job.id, from_state=JobState.XFORM, to_state=JobState.DPX_WRITE)

            shot_dir = self.config.watch.output_dir / job.shot_name
            dpx_dir = shot_dir / "dpx"
            source_stem = source_path.stem
            dpx_path = dpx_dir / f"{source_stem}.dpx"
            self._write_shot_previews(
                shot_dir=shot_dir,
                source_stem=source_stem,
                frame_number=job.frame_number,
                logc=logc,
            )
            write_dpx10_logc_awg(dpx_path, logc)

            if self.config.output.write_debug_tiff:
                debug_path = shot_dir / "debug_linear" / f"{source_stem}.tiff"
                write_linear_debug_tiff(debug_path, decoded.linear_camera_rgb)

            source_sha = sha256_file(source_path)
            self._write_sidecars(
                job=job,
                source_sha256=source_sha,
                dpx_path=dpx_path,
                metadata=_metadata_for_frame(decoded.metadata),
                effective_offset_stops=effective_offset,
            )

            if self.config.output.emit_truth_frame_pack and job.frame_number == self.config.output.truth_frame_index:
                _write_truth_pack(shot_dir, source_stem, logc, dpx_path)

            self.db.mark_done(job.id, output_path=dpx_path, source_sha256=source_sha)
            self.db.mark_shot_frame_done(job.shot_name)
            logger.info("done job=%s -> %s", job.id, dpx_path)

        except MissingDependencyError as exc:
            msg = f"missing dependency for decode: {exc}"
            logger.exception(msg)
            self.db.mark_failed(job.id, msg)
        except DecodeError as exc:
            msg = str(exc)
            logger.exception("decode failed for job=%s", job.id)
            self.db.mark_failed(job.id, msg)
        except Exception as exc:
            msg = f"job failed: {exc}"
            logger.exception("pipeline failed for job=%s", job.id)
            self.db.mark_failed(job.id, msg)

    def _write_shot_previews(
        self,
        *,
        shot_dir: Path,
        source_stem: str,
        frame_number: int,
        logc: np.ndarray,
    ) -> None:
        """Best-effort latest/first shot preview generation for GUI thumbnails."""

        try:
            latest = write_latest_preview(
                shot_dir=shot_dir,
                source_stem=source_stem,
                logc=logc,
                max_edge=PREVIEW_MAX_EDGE,
                quality=PREVIEW_JPEG_QUALITY,
                throttle_seconds=PREVIEW_LATEST_THROTTLE_SECONDS,
            )
            first = update_first_preview_if_earlier(
                shot_dir=shot_dir,
                frame_number=int(frame_number),
                source_stem=source_stem,
                logc=logc,
                max_edge=PREVIEW_MAX_EDGE,
                quality=PREVIEW_JPEG_QUALITY,
            )
            self._maybe_log_preview_warning_once(latest)
            self._maybe_log_preview_warning_once(first)
        except Exception:
            logger.exception("preview generation failed unexpectedly for shot_dir=%s", shot_dir)

    def _maybe_log_preview_warning_once(self, status: PreviewWriteStatus) -> None:
        """Emit warning categories at most once per worker lifecycle."""

        reason = status.reason or ""
        if reason in {"", "throttled", "not_earlier"}:
            return
        if reason in self._preview_warning_once:
            return
        self._preview_warning_once.add(reason)
        if reason == "encoder_unavailable":
            logger.warning("preview encoder unavailable (install Pillow) - previews disabled until dependency is present")
        else:
            logger.warning("preview generation skipped: %s", reason)

    def _write_sidecars(
        self,
        job: Job,
        source_sha256: str,
        dpx_path: Path,
        metadata: dict[str, Any],
        effective_offset_stops: float,
    ) -> None:
        """Persist per-frame metadata and per-shot manifest records."""

        shot_dir = self.config.watch.output_dir / job.shot_name
        shot_dir.mkdir(parents=True, exist_ok=True)

        shot_settings = self.db.get_shot_settings(job.shot_name)
        wb_locked = shot_settings.wb_multipliers if shot_settings else (1.0, 1.0, 1.0, 1.0)
        manifest = ShotManifest(
            shot_name=job.shot_name,
            target_ei=self.config.pipeline.target_ei,
            output_encoding="ARRI LogC3",
            output_gamut="ARRI Wide Gamut",
            locked_wb_multipliers=wb_locked,
            exposure_offset_stops=float(effective_offset_stops),
            pipeline_hash=self.color.version_hash(),
            tool_version=__version__,
            created_at_utc=datetime.now(timezone.utc).isoformat(),
        )
        write_shot_manifest(shot_dir / "manifest.json", manifest)

        if self.config.output.emit_per_frame_json:
            record = FrameRecord(
                shot_name=job.shot_name,
                frame_number=job.frame_number,
                source_filename=Path(job.source_path).name,
                source_sha256=source_sha256,
                dpx_filename=dpx_path.name,
                metadata=metadata,
            )
            write_frame_record(
                shot_dir / "frame_json" / f"{Path(job.source_path).stem}.json",
                record,
            )
