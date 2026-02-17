from __future__ import annotations

from stopmo_xcode.worker import _iso_compensation_stops


def test_iso_compensation_stops_common_values() -> None:
    assert _iso_compensation_stops(200.0, 800) == 2.0
    assert _iso_compensation_stops(100.0, 800) == 3.0
    assert _iso_compensation_stops(800.0, 800) == 0.0


def test_iso_compensation_stops_invalid_values() -> None:
    assert _iso_compensation_stops(None, 800) is None
    assert _iso_compensation_stops(0.0, 800) is None
    assert _iso_compensation_stops(-100.0, 800) is None
    assert _iso_compensation_stops(200.0, 0) is None
