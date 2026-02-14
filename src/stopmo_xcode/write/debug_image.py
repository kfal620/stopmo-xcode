from __future__ import annotations

from pathlib import Path

import numpy as np


def write_linear_debug_tiff(path: Path, rgb: np.ndarray) -> None:
    try:
        import tifffile  # type: ignore
    except Exception as exc:  # pragma: no cover - optional dependency
        raise RuntimeError("tifffile is required for debug TIFF output. Install with: pip install '.[io]'") from exc

    arr = np.asarray(rgb, dtype=np.float32)
    path.parent.mkdir(parents=True, exist_ok=True)
    tifffile.imwrite(str(path), arr, photometric="rgb")
