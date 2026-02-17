from __future__ import annotations

from stopmo_xcode.worker import (
    _aperture_compensation_stops,
    _effective_exposure_offset_stops,
    _iso_compensation_stops,
    _shutter_compensation_stops,
)


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
    value, missing = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=200.0,
        auto_exposure_from_shutter=False,
        target_shutter_s=None,
        frame_shutter_s=None,
        auto_exposure_from_aperture=False,
        target_aperture_f=None,
        frame_aperture_f=None,
        locked_shot_offset_stops=0.0,
    )
    assert missing == ()
    assert value == 2.0


def test_effective_exposure_offset_auto_ignores_stale_locked_offset() -> None:
    value, missing = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=200.0,
        auto_exposure_from_shutter=False,
        target_shutter_s=None,
        frame_shutter_s=None,
        auto_exposure_from_aperture=False,
        target_aperture_f=None,
        frame_aperture_f=None,
        locked_shot_offset_stops=0.0,
    )
    assert missing == ()
    assert value == 2.0


def test_effective_exposure_offset_falls_back_to_locked_offset_when_auto_disabled() -> None:
    value, missing = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=False,
        target_ei=800,
        frame_iso=200.0,
        auto_exposure_from_shutter=False,
        target_shutter_s=None,
        frame_shutter_s=None,
        auto_exposure_from_aperture=False,
        target_aperture_f=None,
        frame_aperture_f=None,
        locked_shot_offset_stops=1.5,
    )
    assert missing == ()
    assert value == 1.5


def test_shutter_compensation_stops_common_values() -> None:
    # 1/10 -> target 1/60 should darken by log2((1/60)/(1/10)) ~= -2.58496 stops
    value = _shutter_compensation_stops(frame_shutter_s=0.1, target_shutter_s=1.0 / 60.0)
    assert value is not None
    assert value < -2.5


def test_aperture_compensation_stops_common_values() -> None:
    # f/2.8 -> target f/4 should darken by -1 stop.
    value = _aperture_compensation_stops(frame_aperture_f=2.8, target_aperture_f=4.0)
    assert value is not None
    assert abs(value + 1.0) < 0.05


def test_effective_exposure_offset_combines_iso_shutter_aperture() -> None:
    value, missing = _effective_exposure_offset_stops(
        base_offset_stops=0.0,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=200.0,
        auto_exposure_from_shutter=True,
        target_shutter_s=1.0 / 60.0,
        frame_shutter_s=0.1,
        auto_exposure_from_aperture=True,
        target_aperture_f=4.0,
        frame_aperture_f=2.8,
        locked_shot_offset_stops=None,
    )
    # +2.0 (ISO) -2.585 (shutter) -1.0 (aperture) ~= -1.585
    assert missing == ()
    assert value < -1.5


def test_effective_exposure_offset_reports_missing_terms() -> None:
    value, missing = _effective_exposure_offset_stops(
        base_offset_stops=0.25,
        auto_exposure_from_iso=True,
        target_ei=800,
        frame_iso=None,
        auto_exposure_from_shutter=True,
        target_shutter_s=None,
        frame_shutter_s=0.1,
        auto_exposure_from_aperture=True,
        target_aperture_f=4.0,
        frame_aperture_f=None,
        locked_shot_offset_stops=None,
    )
    assert value == 0.25
    assert set(missing) == {"iso", "shutter_s", "aperture_f"}
