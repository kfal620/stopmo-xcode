from __future__ import annotations

import numpy as np


# ACES AP0 and ARRI Wide Gamut chromaticities.
AP0_PRIMARIES = np.array([[0.7347, 0.2653], [0.0, 1.0], [0.0001, -0.0770]], dtype=np.float64)
AP0_WHITE = np.array([0.32168, 0.33767], dtype=np.float64)  # ACES white (D60-ish)

AWG_PRIMARIES = np.array([[0.6840, 0.3130], [0.2210, 0.8480], [0.0861, -0.1020]], dtype=np.float64)
AWG_WHITE = np.array([0.3127, 0.3290], dtype=np.float64)  # D65


def _xy_to_xyz(xy: np.ndarray) -> np.ndarray:
    x, y = float(xy[0]), float(xy[1])
    return np.array([x / y, 1.0, (1.0 - x - y) / y], dtype=np.float64)


def rgb_to_xyz_matrix(primaries: np.ndarray, white_xy: np.ndarray) -> np.ndarray:
    xr, yr = primaries[0]
    xg, yg = primaries[1]
    xb, yb = primaries[2]

    xrz = np.array([xr / yr, 1.0, (1.0 - xr - yr) / yr], dtype=np.float64)
    xgz = np.array([xg / yg, 1.0, (1.0 - xg - yg) / yg], dtype=np.float64)
    xbz = np.array([xb / yb, 1.0, (1.0 - xb - yb) / yb], dtype=np.float64)

    m = np.column_stack([xrz, xgz, xbz])
    w = _xy_to_xyz(white_xy)
    s = np.linalg.solve(m, w)
    return m * s


def _bradford_adaptation(src_white_xy: np.ndarray, dst_white_xy: np.ndarray) -> np.ndarray:
    # Bradford CAT.
    m = np.array(
        [[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]],
        dtype=np.float64,
    )
    m_inv = np.linalg.inv(m)

    src_xyz = _xy_to_xyz(src_white_xy)
    dst_xyz = _xy_to_xyz(dst_white_xy)

    src_lms = m @ src_xyz
    dst_lms = m @ dst_xyz

    d = np.diag(dst_lms / src_lms)
    return m_inv @ d @ m


def matrix_aces_to_awg_linear() -> np.ndarray:
    m_ap0_to_xyz = rgb_to_xyz_matrix(AP0_PRIMARIES, AP0_WHITE)
    m_xyz_to_awg = np.linalg.inv(rgb_to_xyz_matrix(AWG_PRIMARIES, AWG_WHITE))
    adapt = _bradford_adaptation(AP0_WHITE, AWG_WHITE)
    return m_xyz_to_awg @ adapt @ m_ap0_to_xyz
