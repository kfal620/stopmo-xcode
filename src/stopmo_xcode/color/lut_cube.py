from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class CubeLUT:
    size: int
    table: np.ndarray
    domain_min: np.ndarray
    domain_max: np.ndarray

    def apply(self, image: np.ndarray) -> np.ndarray:
        x = np.asarray(image, dtype=np.float32)
        dom_min = self.domain_min.astype(np.float32)
        dom_max = self.domain_max.astype(np.float32)
        span = np.maximum(dom_max - dom_min, 1e-6)

        t = (x - dom_min) / span
        t = np.clip(t, 0.0, 1.0)
        t = t * (self.size - 1)

        i0 = np.floor(t).astype(np.int32)
        i1 = np.clip(i0 + 1, 0, self.size - 1)
        f = t - i0

        r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
        r1, g1, b1 = i1[..., 0], i1[..., 1], i1[..., 2]
        fr, fg, fb = f[..., 0], f[..., 1], f[..., 2]

        c000 = self.table[r0, g0, b0]
        c100 = self.table[r1, g0, b0]
        c010 = self.table[r0, g1, b0]
        c110 = self.table[r1, g1, b0]
        c001 = self.table[r0, g0, b1]
        c101 = self.table[r1, g0, b1]
        c011 = self.table[r0, g1, b1]
        c111 = self.table[r1, g1, b1]

        c00 = c000 * (1 - fr)[..., None] + c100 * fr[..., None]
        c10 = c010 * (1 - fr)[..., None] + c110 * fr[..., None]
        c01 = c001 * (1 - fr)[..., None] + c101 * fr[..., None]
        c11 = c011 * (1 - fr)[..., None] + c111 * fr[..., None]

        c0 = c00 * (1 - fg)[..., None] + c10 * fg[..., None]
        c1 = c01 * (1 - fg)[..., None] + c11 * fg[..., None]

        out = c0 * (1 - fb)[..., None] + c1 * fb[..., None]
        return out.astype(np.float32)


def load_cube(path: Path) -> CubeLUT:
    size = None
    domain_min = np.array([0.0, 0.0, 0.0], dtype=np.float32)
    domain_max = np.array([1.0, 1.0, 1.0], dtype=np.float32)
    values: list[list[float]] = []

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            head = parts[0].upper()
            if head == "TITLE":
                continue
            if head == "LUT_3D_SIZE":
                size = int(parts[1])
                continue
            if head == "DOMAIN_MIN":
                domain_min = np.array([float(parts[1]), float(parts[2]), float(parts[3])], dtype=np.float32)
                continue
            if head == "DOMAIN_MAX":
                domain_max = np.array([float(parts[1]), float(parts[2]), float(parts[3])], dtype=np.float32)
                continue

            if len(parts) >= 3:
                values.append([float(parts[0]), float(parts[1]), float(parts[2])])

    if size is None:
        raise ValueError(f"missing LUT_3D_SIZE in {path}")

    arr = np.asarray(values, dtype=np.float32)
    expected = size * size * size
    if arr.shape[0] != expected:
        raise ValueError(f"invalid LUT size in {path}: expected {expected} rows, got {arr.shape[0]}")

    table = arr.reshape((size, size, size, 3), order="F")
    return CubeLUT(size=size, table=table, domain_min=domain_min, domain_max=domain_max)
