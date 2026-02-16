from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any

import numpy as np

from stopmo_xcode.color.primaries import AP0_PRIMARIES, AP0_WHITE, rgb_to_xyz_matrix


D65_WHITE = np.array([0.3127, 0.3290], dtype=np.float64)

# dcraw/LibRaw-style camera -> XYZ (D65) constants, scaled by 1/10000.
KNOWN_CAMERA_TO_XYZ_D65: dict[str, np.ndarray] = {
    "canon eos r": np.array(
        [
            [6445, -366, -864],
            [-4436, 12204, 2513],
            [-952, 2496, 6348],
        ],
        dtype=np.float64,
    )
    / 10000.0,
}


@dataclass
class MatrixSuggestion:
    input_path: Path
    camera_make: str | None
    camera_model: str | None
    source: str
    confidence: str
    reference_space: str
    camera_to_reference_matrix: tuple[tuple[float, float, float], ...]
    assumptions: tuple[str, ...]
    warnings: tuple[str, ...]
    notes: tuple[str, ...]

    def to_json_dict(self) -> dict[str, Any]:
        return {
            "input_path": str(self.input_path),
            "camera_make": self.camera_make,
            "camera_model": self.camera_model,
            "source": self.source,
            "confidence": self.confidence,
            "reference_space": self.reference_space,
            "camera_to_reference_matrix": [[float(v) for v in row] for row in self.camera_to_reference_matrix],
            "assumptions": list(self.assumptions),
            "warnings": list(self.warnings),
            "notes": list(self.notes),
        }

    def to_yaml_block(self) -> str:
        rows = [
            f"    - [{row[0]:.8f}, {row[1]:.8f}, {row[2]:.8f}]"
            for row in self.camera_to_reference_matrix
        ]
        return "\n".join(["pipeline:", "  camera_to_reference_matrix:", *rows])


def _normalize_camera_key(make: str | None, model: str | None) -> str | None:
    text = " ".join([v for v in [make, model] if v]).strip().lower()
    if not text:
        return None
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    return text or None


def lookup_known_camera_to_xyz_d65(make: str | None, model: str | None) -> np.ndarray | None:
    key = _normalize_camera_key(make, model)
    if key is None:
        return None
    if key in KNOWN_CAMERA_TO_XYZ_D65:
        return KNOWN_CAMERA_TO_XYZ_D65[key].copy()
    # Common shorthand (e.g., "EOS R")
    model_only = _normalize_camera_key(None, model)
    if model_only:
        candidate = f"canon {model_only}"
        if candidate in KNOWN_CAMERA_TO_XYZ_D65:
            return KNOWN_CAMERA_TO_XYZ_D65[candidate].copy()
    return None


def _xy_to_xyz(xy: np.ndarray) -> np.ndarray:
    x, y = float(xy[0]), float(xy[1])
    return np.array([x / y, 1.0, (1.0 - x - y) / y], dtype=np.float64)


def _bradford_adaptation(src_white_xy: np.ndarray, dst_white_xy: np.ndarray) -> np.ndarray:
    m = np.array(
        [
            [0.8951, 0.2664, -0.1614],
            [-0.7502, 1.7135, 0.0367],
            [0.0389, -0.0685, 1.0296],
        ],
        dtype=np.float64,
    )
    m_inv = np.linalg.inv(m)

    src_xyz = _xy_to_xyz(src_white_xy)
    dst_xyz = _xy_to_xyz(dst_white_xy)

    src_lms = m @ src_xyz
    dst_lms = m @ dst_xyz
    d = np.diag(dst_lms / src_lms)
    return m_inv @ d @ m


def _camera_xyz_d65_to_aces2065_1(camera_to_xyz_d65: np.ndarray) -> np.ndarray:
    xyz_d65_to_xyz_d60 = _bradford_adaptation(D65_WHITE, AP0_WHITE)
    xyz_d60_to_ap0 = np.linalg.inv(rgb_to_xyz_matrix(AP0_PRIMARIES, AP0_WHITE))
    return xyz_d60_to_ap0 @ xyz_d65_to_xyz_d60 @ camera_to_xyz_d65


def _coerce_to_3x3(value: Any) -> tuple[np.ndarray | None, list[str]]:
    notes: list[str] = []
    if value is None:
        return None, notes

    try:
        arr = np.asarray(value, dtype=np.float64)
    except Exception:
        return None, notes

    if arr.ndim != 2:
        return None, notes

    if arr.shape == (4, 3):
        # LibRaw sometimes stores a second green row; average both green rows.
        arr = np.vstack([arr[0], 0.5 * (arr[1] + arr[3]), arr[2]])
        notes.append("Reduced 4x3 matrix to 3x3 by averaging green rows (G/G2).")
    elif arr.shape == (3, 4):
        arr = arr[:, :3]
        notes.append("Reduced 3x4 matrix to 3x3 by dropping 4th column.")
    elif arr.shape == (4, 4):
        arr = arr[:3, :3]
        notes.append("Reduced 4x4 matrix to 3x3 by taking top-left block.")
    elif arr.shape != (3, 3):
        return None, notes

    if not np.isfinite(arr).all():
        return None, notes

    if np.allclose(arr, 0.0):
        return None, notes

    if np.max(np.abs(arr)) > 10.0:
        arr = arr / 10000.0
        notes.append("Detected integer-scaled matrix and normalized by 1/10000.")

    return arr.astype(np.float64), notes


def _extract_make_model_exiftool(path: Path) -> tuple[str | None, str | None]:
    exiftool = shutil.which("exiftool")
    if exiftool is None:
        return None, None

    try:
        proc = subprocess.run(
            [exiftool, "-j", "-Make", "-Model", str(path)],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            return None, None
        rows = json.loads(proc.stdout)
        if not rows:
            return None, None
        row = rows[0]
        make = row.get("Make")
        model = row.get("Model")
        return (str(make).strip() if make else None, str(model).strip() if model else None)
    except Exception:
        return None, None


def suggest_camera_to_reference_matrix(
    path: Path,
    reference_space: str = "ACES2065-1",
    camera_make_override: str | None = None,
    camera_model_override: str | None = None,
) -> MatrixSuggestion:
    if reference_space != "ACES2065-1":
        raise ValueError("Only ACES2065-1 reference is currently supported.")

    raw_path = path.expanduser().resolve()
    if not raw_path.exists():
        raise FileNotFoundError(raw_path)

    assumptions = [
        "Input matrix is interpreted as camera-linear RGB -> CIE XYZ under D65.",
        "Chromatic adaptation uses Bradford D65 -> D60.",
        "Reference conversion is XYZ(D60) -> ACES2065-1 (AP0).",
    ]
    warnings: list[str] = []
    notes: list[str] = []

    make: str | None = None
    model: str | None = None
    camera_to_xyz_d65: np.ndarray | None = None
    source = ""
    confidence = "low"

    try:
        import rawpy  # type: ignore
    except Exception:
        rawpy = None
        warnings.append("rawpy is unavailable; skipping matrix extraction from RAW metadata.")

    if rawpy is not None:
        try:
            with rawpy.imread(str(raw_path)) as raw:
                metadata = getattr(raw, "metadata", None)
                if metadata is not None:
                    make_v = getattr(metadata, "make", None)
                    model_v = getattr(metadata, "model", None)
                    make = str(make_v).strip() if make_v else None
                    model = str(model_v).strip() if model_v else None

                rgb_xyz = getattr(raw, "rgb_xyz_matrix", None)
                camera_to_xyz_d65, extra_notes = _coerce_to_3x3(rgb_xyz)
                if camera_to_xyz_d65 is not None:
                    source = "rawpy.rgb_xyz_matrix"
                    confidence = "high"
                    notes.extend(extra_notes)

                if camera_to_xyz_d65 is None:
                    color_matrix = getattr(raw, "color_matrix", None)
                    camera_to_xyz_d65, extra_notes = _coerce_to_3x3(color_matrix)
                    if camera_to_xyz_d65 is not None:
                        source = "rawpy.color_matrix"
                        confidence = "medium"
                        notes.extend(extra_notes)
                        warnings.append(
                            "Using rawpy.color_matrix; verify direction (camera->XYZ) against chart footage before production."
                        )
        except Exception as exc:
            warnings.append(f"rawpy failed to decode file metadata: {exc}")

    if make is None and model is None:
        make_e, model_e = _extract_make_model_exiftool(raw_path)
        make = make or make_e
        model = model or model_e

    if camera_make_override:
        make = camera_make_override.strip() or make
        notes.append("Camera make was overridden from CLI input.")
    if camera_model_override:
        model = camera_model_override.strip() or model
        notes.append("Camera model was overridden from CLI input.")

    if camera_to_xyz_d65 is None:
        fallback = lookup_known_camera_to_xyz_d65(make, model)
        if fallback is not None:
            camera_to_xyz_d65 = fallback
            source = "known_camera_table.dcraw"
            confidence = "medium"
            notes.append("Used built-in fallback matrix from known camera table.")
        else:
            raise RuntimeError(
                "No camera matrix found in RAW metadata and no known fallback for this camera model."
            )

    det = float(np.linalg.det(camera_to_xyz_d65))
    if abs(det) < 1e-8:
        warnings.append("Camera->XYZ matrix is near-singular; validate result before use.")

    camera_to_ref = _camera_xyz_d65_to_aces2065_1(camera_to_xyz_d65)
    matrix = tuple(tuple(float(v) for v in row) for row in camera_to_ref.tolist())

    return MatrixSuggestion(
        input_path=raw_path,
        camera_make=make,
        camera_model=model,
        source=source,
        confidence=confidence,
        reference_space=reference_space,
        camera_to_reference_matrix=matrix,
        assumptions=tuple(assumptions),
        warnings=tuple(warnings),
        notes=tuple(notes),
    )
