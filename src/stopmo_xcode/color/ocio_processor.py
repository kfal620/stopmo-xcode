from __future__ import annotations

from pathlib import Path

import numpy as np


try:
    import PyOpenColorIO as ocio  # type: ignore
except Exception:  # pragma: no cover - optional
    ocio = None


class OcioUnavailableError(RuntimeError):
    pass


class OcioImageProcessor:
    def __init__(self, config_path: Path, input_space: str, output_space: str) -> None:
        if ocio is None:
            raise OcioUnavailableError("PyOpenColorIO not installed. Install with: pip install '.[ocio]'")

        self._config = ocio.Config.CreateFromFile(str(config_path))
        self._processor = self._config.getProcessor(input_space, output_space)
        self._cpu = self._processor.getDefaultCPUProcessor()

    def apply(self, rgb: np.ndarray) -> np.ndarray:
        out = np.asarray(rgb, dtype=np.float32).copy()
        h, w, c = out.shape
        if c != 3:
            raise ValueError(f"expected 3 channels, got {c}")
        flat = out.reshape((-1, 3))
        self._cpu.applyRGB(flat)
        return flat.reshape((h, w, 3))
