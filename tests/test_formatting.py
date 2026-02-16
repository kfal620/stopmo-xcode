from __future__ import annotations

from stopmo_xcode.utils.formatting import shutter_seconds_to_fraction


def test_shutter_seconds_to_fraction_common_values() -> None:
    assert shutter_seconds_to_fraction(1 / 60) == "1/60"
    assert shutter_seconds_to_fraction(0.1) == "1/10"


def test_shutter_seconds_to_fraction_invalid_values() -> None:
    assert shutter_seconds_to_fraction(None) is None
    assert shutter_seconds_to_fraction(0.0) is None
    assert shutter_seconds_to_fraction(-1.0) is None
