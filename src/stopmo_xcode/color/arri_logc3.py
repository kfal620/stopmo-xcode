from __future__ import annotations

import numpy as np


# ARRI LogC3 constants for EI800 (SUP 3.x style), normalized signal domain.
_LOGC3_EI800 = {
    "cut": 0.010591,
    "a": 5.555556,
    "b": 0.052272,
    "c": 0.247190,
    "d": 0.385537,
    "e": 5.367655,
    "f": 0.092809,
}


def encode_logc3_ei800(linear_awg: np.ndarray) -> np.ndarray:
    """Encode linear AWG RGB to LogC3 EI800.

    Input and output are normalized floats in [0, +inf) and roughly [0, 1+].
    Negative values are clipped before encoding.
    """

    params = _LOGC3_EI800
    x = np.asarray(linear_awg, dtype=np.float32)
    x = np.maximum(x, 0.0)

    cut = params["cut"]
    high = params["c"] * np.log10(params["a"] * x + params["b"]) + params["d"]
    low = params["e"] * x + params["f"]
    y = np.where(x > cut, high, low)
    return y.astype(np.float32)


def decode_logc3_ei800(logc: np.ndarray) -> np.ndarray:
    """Inverse of encode_logc3_ei800 for diagnostics/tests."""

    params = _LOGC3_EI800
    y = np.asarray(logc, dtype=np.float32)

    cut_y = params["e"] * params["cut"] + params["f"]
    high = (np.power(10.0, (y - params["d"]) / params["c"]) - params["b"]) / params["a"]
    low = (y - params["f"]) / params["e"]
    x = np.where(y > cut_y, high, low)
    return np.maximum(x, 0.0).astype(np.float32)
