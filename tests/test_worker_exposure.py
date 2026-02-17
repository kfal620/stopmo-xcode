from __future__ import annotations

from stopmo_xcode.worker import _effective_exposure_offset_stops, _iso_compensation_stops


def test_iso_compensation_stops_common_values() -> None:
    assert _iso_compensation_stops(200.0, 800) == 2.0
    assert _iso_compensation_stops(100.0, 800) == 3.0
    assert _iso_compensation_stops(800.0, 800) == 0.0


def test_iso_compensation_stops_invalid_values() -> None:
    assert _iso_compensation_stops(None, 800) is None
    assert _iso_compensation_stops(0.0, 800) is None
    assert _iso_compensation_stops(-100.0, 800) is None
    assert _iso_compensation_stops(200.0, 0) is None


def test_effective_exposure_offset_uses_auto_when_enabled() -> None:
    value, ok = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=200.0,
        locked_shot_offset_stops=0.0,
    )
    assert ok is True
    assert value == 2.0


def test_effective_exposure_offset_auto_ignores_stale_locked_offset() -> None:
    value, ok = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=200.0,
        locked_shot_offset_stops=0.0,
    )
    assert ok is True
    assert value == 2.0


def test_effective_exposure_offset_falls_back_to_locked_offset_when_auto_disabled() -> None:
    value, ok = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=False,
        target_ei=800,
        frame_iso=200.0,
        locked_shot_offset_stops=1.5,
    )
    assert ok is True
    assert value == 1.5
