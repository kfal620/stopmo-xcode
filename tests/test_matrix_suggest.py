from __future__ import annotations

import numpy as np

from stopmo_xcode.color.matrix_suggest import (
    _camera_xyz_d65_to_aces2065_1,
    _coerce_to_3x3,
    lookup_known_camera_to_xyz_d65,
)


def test_lookup_known_camera_to_xyz_d65_eos_r() -> None:
    m = lookup_known_camera_to_xyz_d65("Canon", "EOS R")
    assert m is not None
    assert m.shape == (3, 3)
    assert np.allclose(
        m,
        np.array(
            [
                [0.6445, -0.0366, -0.0864],
                [-0.4436, 1.2204, 0.2513],
                [-0.0952, 0.2496, 0.6348],
            ],
            dtype=np.float64,
        ),
        atol=1e-8,
    )


def test_lookup_known_camera_to_xyz_d65_eos_r_model_only() -> None:
    m = lookup_known_camera_to_xyz_d65(None, "EOS R")
    assert m is not None
    assert m.shape == (3, 3)


def test_camera_xyz_d65_to_aces2065_1_eos_r_reference_values() -> None:
    camera_to_xyz = lookup_known_camera_to_xyz_d65("Canon", "EOS R")
    assert camera_to_xyz is not None
    out = _camera_xyz_d65_to_aces2065_1(camera_to_xyz)
    expected = np.array(
        [
            [0.68408466, -0.03504787, -0.1003096],
            [-0.93278097, 1.7105875, 0.44433053],
            [-0.09111841, 0.23450891, 0.58315293],
        ],
        dtype=np.float64,
    )
    assert np.allclose(out, expected, atol=1e-6)


def test_coerce_to_3x3_averages_green_rows_for_4x3() -> None:
    raw = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, 2.0, 0.0],
            [0.0, 0.0, 3.0],
            [0.0, 4.0, 0.0],
        ],
        dtype=np.float64,
    )
    out, notes = _coerce_to_3x3(raw)
    assert out is not None
    assert np.allclose(
        out,
        np.array(
            [
                [1.0, 0.0, 0.0],
                [0.0, 3.0, 0.0],
                [0.0, 0.0, 3.0],
            ],
            dtype=np.float64,
        ),
    )
    assert any("averaging green rows" in n.lower() for n in notes)
