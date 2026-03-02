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
        frame_number=1,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert first.wrote is True
    assert first.path is not None and first.path.exists()
    latest_meta = json.loads((shot_dir / "preview" / "latest.meta.json").read_text(encoding="utf-8"))
    assert latest_meta["render_intent"] == "logc_awg"

    second = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_A_0002",
        frame_number=2,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert second.wrote is True
    assert second.skipped is False


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
    assert payload["render_intent"] == "logc_awg"


def test_preview_writer_handles_missing_encoder_gracefully(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: None)
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_tiff", lambda *args, **kwargs: None)
    shot_dir = tmp_path / "SHOT_C"

    latest = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_C_0001",
        frame_number=1,
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


def test_latest_preview_removes_stale_alternate_variant(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: None)
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_tiff", lambda *args, **kwargs: b"tiff-a")
    shot_dir = tmp_path / "SHOT_D"
    preview_dir = shot_dir / "preview"
    preview_dir.mkdir(parents=True, exist_ok=True)
    stale_jpg = preview_dir / "latest.jpg"
    stale_jpg.write_bytes(b"stale")

    latest = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_D_0001",
        frame_number=1,
        logc=_dummy_logc(),
        throttle_seconds=0.0,
    )
    assert latest.wrote is True
    assert latest.path is not None
    assert latest.path.suffix == ".tiff"
    assert not stale_jpg.exists()


def test_write_latest_preview_rewrites_when_render_intent_missing(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"fresh")
    shot_dir = tmp_path / "SHOT_E"
    preview_dir = shot_dir / "preview"
    preview_dir.mkdir(parents=True, exist_ok=True)
    latest_path = preview_dir / "latest.jpg"
    latest_path.write_bytes(b"stale")
    (preview_dir / "latest.meta.json").write_text(
        json.dumps({"updated_at_utc": "2026-01-01T00:00:00+00:00", "source_stem": "SHOT_E_0001"}) + "\n",
        encoding="utf-8",
    )

    result = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_E_0002",
        frame_number=2,
        logc=_dummy_logc(),
        throttle_seconds=60.0,
    )

    assert result.wrote is True
    assert latest_path.read_bytes() == b"fresh"
    payload = json.loads((preview_dir / "latest.meta.json").read_text(encoding="utf-8"))
    assert payload["render_intent"] == "logc_awg"


def test_write_latest_preview_throttles_when_frame_does_not_advance(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"jpeg-same")
    shot_dir = tmp_path / "SHOT_G"

    first = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_G_0001",
        frame_number=1,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert first.wrote is True

    second = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_G_0001_DUP",
        frame_number=1,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert second.wrote is False
    assert second.skipped is True
    assert second.reason == "throttled"


def test_write_latest_preview_skips_older_frame(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"jpeg-newer")
    shot_dir = tmp_path / "SHOT_H"

    newer = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_H_0010",
        frame_number=10,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert newer.wrote is True

    older = write_latest_preview(
        shot_dir=shot_dir,
        source_stem="SHOT_H_0005",
        frame_number=5,
        logc=_dummy_logc(),
        throttle_seconds=10.0,
    )
    assert older.wrote is False
    assert older.skipped is True
    assert older.reason == "not_later_frame"


def test_first_preview_rewrites_when_render_intent_missing_even_if_not_earlier(
    monkeypatch, tmp_path: Path
) -> None:
    monkeypatch.setattr("stopmo_xcode.write.previews._encode_preview_jpeg", lambda *args, **kwargs: b"fresh-first")
    shot_dir = tmp_path / "SHOT_F"
    preview_dir = shot_dir / "preview"
    preview_dir.mkdir(parents=True, exist_ok=True)
    first_path = preview_dir / "first.jpg"
    first_path.write_bytes(b"stale-first")
    (preview_dir / "first.meta.json").write_text(
        json.dumps(
            {
                "frame_number": 10,
                "updated_at_utc": "2026-01-01T00:00:00+00:00",
                "source_stem": "SHOT_F_0010",
            }
        )
        + "\n",
        encoding="utf-8",
    )

    result = update_first_preview_if_earlier(
        shot_dir=shot_dir,
        frame_number=20,
        source_stem="SHOT_F_0020",
        logc=_dummy_logc(),
    )

    assert result.wrote is True
    assert first_path.read_bytes() == b"fresh-first"
    payload = json.loads((preview_dir / "first.meta.json").read_text(encoding="utf-8"))
    assert payload["render_intent"] == "logc_awg"
