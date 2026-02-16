from __future__ import annotations

from stopmo_xcode.decode.exif_metadata import _ratio_like_to_float


class _Ratio:
    def __init__(self, num: int, den: int) -> None:
        self.num = num
        self.den = den


def test_ratio_like_to_float_ratio_object() -> None:
    assert _ratio_like_to_float(_Ratio(1, 50)) == 0.02


def test_ratio_like_to_float_list_wrapper() -> None:
    assert _ratio_like_to_float([_Ratio(4, 1)]) == 4.0


def test_ratio_like_to_float_plain_value() -> None:
    assert _ratio_like_to_float("200") == 200.0
