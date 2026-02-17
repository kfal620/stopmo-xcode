from __future__ import annotations

import hashlib
import json
from typing import Any

import numpy as np

from stopmo_xcode.config import PipelineConfig

from .arri_logc3 import encode_logc3_ei800
from .lut_cube import CubeLUT, load_cube
from .ocio_processor import OcioImageProcessor
from .primaries import matrix_aces_to_awg_linear


class ColorPipeline:
    """Deterministic color pipeline from camera-linear to LogC3/AWG."""

    def __init__(self, cfg: PipelineConfig) -> None:
        self.cfg = cfg
        self._camera_to_ref = np.asarray(cfg.camera_to_reference_matrix, dtype=np.float32)
        self._aces_to_awg = matrix_aces_to_awg_linear().astype(np.float32)
        self._contrast = float(cfg.contrast)
        self._contrast_pivot_linear = float(cfg.contrast_pivot_linear)
        self._contrast_pivot_logc = float(
            encode_logc3_ei800(
                np.array(
                    [[[self._contrast_pivot_linear, self._contrast_pivot_linear, self._contrast_pivot_linear]]],
                    dtype=np.float32,
                )
            )[0, 0, 1]
        )
        self._lut: CubeLUT | None = None

        if cfg.apply_match_lut and cfg.match_lut_path is not None:
            self._lut = load_cube(cfg.match_lut_path)

        self._ocio: OcioImageProcessor | None = None
        if cfg.use_ocio:
            if cfg.ocio_config_path is None:
                raise ValueError("pipeline.use_ocio=true requires pipeline.ocio_config_path")
            self._ocio = OcioImageProcessor(
                config_path=cfg.ocio_config_path,
                input_space=cfg.ocio_input_space,
                output_space=cfg.ocio_output_space,
            )

    def transform(self, linear_camera_rgb: np.ndarray, exposure_offset_stops: float | None = None) -> np.ndarray:
        x = np.asarray(linear_camera_rgb, dtype=np.float32)

        if self._ocio is not None:
            return self._ocio.apply(x)

        ref = np.einsum("ij,...j->...i", self._camera_to_ref, x, optimize=True)
        awg = np.einsum("ij,...j->...i", self._aces_to_awg, ref, optimize=True)

        effective_exposure = (
            float(self.cfg.exposure_offset_stops)
            if exposure_offset_stops is None
            else float(exposure_offset_stops)
        )
        if effective_exposure != 0.0:
            awg = awg * (2.0 ** effective_exposure)

        if self._lut is not None:
            awg = self._lut.apply(awg)

        logc = encode_logc3_ei800(awg)
        if self._contrast != 1.0:
            logc = self._contrast_pivot_logc + (logc - self._contrast_pivot_logc) * self._contrast
            logc = np.clip(logc, 0.0, 1.0)
        return logc

    def version_hash(self) -> str:
        payload: dict[str, Any] = {
            "camera_to_reference_matrix": [[float(v) for v in row] for row in self.cfg.camera_to_reference_matrix],
            "exposure_offset_stops": float(self.cfg.exposure_offset_stops),
            "auto_exposure_from_iso": bool(self.cfg.auto_exposure_from_iso),
            "auto_exposure_from_shutter": bool(self.cfg.auto_exposure_from_shutter),
            "target_shutter_s": float(self.cfg.target_shutter_s) if self.cfg.target_shutter_s is not None else None,
            "auto_exposure_from_aperture": bool(self.cfg.auto_exposure_from_aperture),
            "target_aperture_f": float(self.cfg.target_aperture_f) if self.cfg.target_aperture_f is not None else None,
            "contrast": float(self.cfg.contrast),
            "contrast_pivot_linear": float(self.cfg.contrast_pivot_linear),
            "target_ei": int(self.cfg.target_ei),
            "apply_match_lut": bool(self.cfg.apply_match_lut),
            "match_lut_path": str(self.cfg.match_lut_path) if self.cfg.match_lut_path else None,
            "use_ocio": bool(self.cfg.use_ocio),
            "ocio_config_path": str(self.cfg.ocio_config_path) if self.cfg.ocio_config_path else None,
            "ocio_input_space": self.cfg.ocio_input_space,
            "ocio_output_space": self.cfg.ocio_output_space,
        }
        blob = json.dumps(payload, sort_keys=True).encode("utf-8")
        return hashlib.sha256(blob).hexdigest()[:16]
