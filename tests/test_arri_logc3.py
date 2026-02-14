from __future__ import annotations

import numpy as np

from stopmo_xcode.color.arri_logc3 import decode_logc3_ei800, encode_logc3_ei800


def test_logc3_roundtrip() -> None:
    x = np.linspace(0.0, 4.0, 1024, dtype=np.float32)
    x = np.stack([x, x, x], axis=-1)

    y = encode_logc3_ei800(x)
    z = decode_logc3_ei800(y)

    assert np.allclose(z, x, atol=2e-4, rtol=2e-4)


def test_logc3_monotonic() -> None:
    x = np.linspace(0.0, 8.0, 2048, dtype=np.float32)
    y = encode_logc3_ei800(x)
    dy = np.diff(y)
    assert np.all(dy >= 0.0)
