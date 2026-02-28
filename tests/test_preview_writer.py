from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from stopmo_xcode.write.previews import update_first_preview_if_earlier, write_latest_preview


def _dummy_logc(height: int = 24, width: int = 32) -> np.ndarray:
    return np.zeros((height, width, 3), dtype=np.float32)


def test_write_latest_preview_writes_then_throttles(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"jpeg-a")
    shot_dir = tmp_path / "SHOT_A"

    first = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_A_0001",
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert first.wrote is True
    assert first.path is not None and first.path.exists()

    second = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_A_0002",
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert second.wrote is False
    assert second.skipped is True
    assert second.reason == "throttled"


def test_first_preview_replaced_when_earlier_frame_arrives(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"jpeg-b")
    shot_dir = tmp_path / "SHOT_B"

    write_first = update_first_preview_if_earlier(
        shot_dir=shot_dir,
        frame_number=12,
        source_stem="SHOT_B_0012",
        logc=_dummy_logc(),
    )
    assert write_first.wrote is True

    keep_first = update_first_preview_if_earlier(
        shot_dir=shot_dir,
        frame_number=20,
        source_stem="SHOT_B_0020",
        logc=_dummy_logc(),
    )
    assert keep_first.wrote is False
    assert keep_first.reason == "not_earlier"

    replace_first = update_first_preview_if_earlier(
        shot_dir=shot_dir,
        frame_number=5,
        source_stem="SHOT_B_0005",
        logc=_dummy_logc(),
    )
    assert replace_first.wrote is True

    meta_path = shot_dir / "preview" / "first.meta.json"
    payload = json.loads(meta_path.read_text(encoding="utf-8"))
    assert payload["frame_number"] == 5
    assert payload["source_stem"] == "SHOT_B_0005"


def test_preview_writer_handles_missing_encoder_gracefully(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: None)
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_tiff", lambda *args, **kwargs: None)
    shot_dir = tmp_path / "SHOT_C"

    latest = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_C_0001",
        logc=_dummy_logc(),
    )
    first = update_first_preview_if_earlier(
        shot_dir=shot_dir,
        frame_number=1,
        source_stem="SHOT_C_0001",
        logc=_dummy_logc(),
    )

    assert latest.wrote is False
    assert latest.reason == "encoder_unavailable"
    assert first.wrote is False
    assert first.reason == "encoder_unavailable"
