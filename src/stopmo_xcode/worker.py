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
    ShotManifest,
    write_dpx10_logc_awg,
    write_frame_record,
    write_linear_debug_tiff,
    write_shot_manifest,
)


logger = logging.getLogger(__name__)


def _warn_nan_inf(rgb: np.ndarray, source_path: Path) -> None:
    if not np.isfinite(rgb).all():
        logger.warning("non-finite values detected in decoded frame: %s", source_path)


def _warn_clipping(rgb: np.ndarray, source_path: Path, threshold: float = 0.01) -> None:
    clipped = np.mean(rgb >= 1.0)
    if clipped > threshold:
        logger.warning("high pre-log clipping ratio %.2f%% in %s", clipped * 100.0, source_path)


def _wb_delta(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    av = np.array(a, dtype=np.float32)
    bv = np.array(b, dtype=np.float32)
    return float(np.max(np.abs(av - bv)))


def _iso_compensation_stops(iso: float | None, target_ei: int) -> float | None:
    if iso is None or iso <= 0.0 or target_ei <= 0:
        return None
    return float(math.log2(float(target_ei) / float(iso)))


def _effective_exposure_offset_stops(
    base_offset_stops: float,
    auto_exposure_from_iso: bool,
    target_ei: int,
    frame_iso: float | None,
    locked_shot_offset_stops: float | None,
) -> tuple[float, bool]:
    if auto_exposure_from_iso:
        iso_stops = _iso_compensation_stops(frame_iso, target_ei)
        if iso_stops is None:
            return float(base_offset_stops), False
        return float(base_offset_stops) + float(iso_stops), True

    if locked_shot_offset_stops is not None:
        return float(locked_shot_offset_stops), True

    return float(base_offset_stops), True


def _write_truth_pack(
    shot_dir: Path,
    source_stem: str,
    logc: np.ndarray,
    dpx_path: Path,
) -> None:
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
    data = asdict(meta)
    data["source_path"] = str(meta.source_path)
    data["shutter_s"] = shutter_seconds_to_fraction(meta.shutter_s)
    return data


class JobProcessor:
    def __init__(self, config: AppConfig, db: QueueDB) -> None:
        self.config = config
        self.db = db
        self.decoder: DecoderRegistry | None = None
        self._decoder_init_error: Exception | None = None
        try:
            self.decoder = DecoderRegistry()
        except Exception as exc:
            self._decoder_init_error = exc
        self.color = ColorPipeline(config.pipeline)

    def process_job(self, job: Job) -> None:
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

            effective_offset, has_effective = _effective_exposure_offset_stops(
                base_offset_stops=float(self.config.pipeline.exposure_offset_stops),
                auto_exposure_from_iso=bool(self.config.pipeline.auto_exposure_from_iso),
                target_ei=int(self.config.pipeline.target_ei),
                frame_iso=decoded.metadata.iso,
                locked_shot_offset_stops=(
                    float(shot_settings.exposure_offset_stops) if shot_settings is not None else None
                ),
            )
            if self.config.pipeline.auto_exposure_from_iso and not has_effective:
                logger.warning(
                    "auto_exposure_from_iso enabled but ISO metadata is missing/invalid for %s; using base offset",
                    source_path.name,
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

    def _write_sidecars(
        self,
        job: Job,
        source_sha256: str,
        dpx_path: Path,
        metadata: dict[str, Any],
        effective_offset_stops: float,
    ) -> None:
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
