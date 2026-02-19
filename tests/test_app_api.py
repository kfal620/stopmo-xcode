from __future__ import annotations

import json
from pathlib import Path

from stopmo_xcode import app_api
from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB


def _write_min_config(tmp_path: Path) -> Path:
    cfg = tmp_path / "config.yaml"
    cfg.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
""",
        encoding="utf-8",
    )
    return cfg


def test_get_status_returns_typed_payload(tmp_path: Path) -> None:
    cfg_path = _write_min_config(tmp_path)
    cfg = load_config(cfg_path)

    src = cfg.watch.source_dir / "SHOT_A_0001.CR3"
    src.write_bytes(b"x")

    db = QueueDB(cfg.watch.db_path)
    try:
        assert db.enqueue_detected(src, shot_name="SHOT_A", frame_number=1)
    finally:
        db.close()

    status = app_api.get_status(cfg_path, limit=10)
    assert status.db_path == str(cfg.watch.db_path)
    assert status.counts.get("detected") == 1
    assert len(status.recent) == 1
    assert status.recent[0].shot == "SHOT_A"
    assert status.recent[0].frame == 1
    assert Path(status.recent[0].source).name == "SHOT_A_0001.CR3"


def test_suggest_matrix_writes_json_when_requested(tmp_path: Path, monkeypatch) -> None:
    frame = tmp_path / "frame.CR3"
    frame.write_bytes(b"x")
    output_json = tmp_path / "reports" / "suggest.json"

    class _FakeReport:
        camera_make = "Canon"
        camera_model = "EOS R"
        source = "known_camera_table.dcraw"
        confidence = "medium"
        assumptions = ("a",)
        notes = ("n",)
        warnings = ()
        input_path = frame.resolve()

        def to_json_dict(self) -> dict[str, object]:
            return {
                "input_path": str(frame.resolve()),
                "camera_make": "Canon",
                "camera_model": "EOS R",
                "source": "known_camera_table.dcraw",
                "confidence": "medium",
                "reference_space": "ACES2065-1",
                "camera_to_reference_matrix": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
                "assumptions": ["a"],
                "warnings": [],
                "notes": ["n"],
            }

        def to_yaml_block(self) -> str:
            return "pipeline:\n  camera_to_reference_matrix:\n    - [1, 0, 0]\n    - [0, 1, 0]\n    - [0, 0, 1]"

    monkeypatch.setattr(app_api, "suggest_camera_to_reference_matrix", lambda *args, **kwargs: _FakeReport())

    result = app_api.suggest_matrix(
        input_path=frame,
        camera_make_override="Canon",
        camera_model_override="EOS R",
        write_json_path=output_json,
    )

    assert result.json_report_path == output_json.resolve()
    assert output_json.exists()

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["camera_make"] == "Canon"
    assert payload["camera_model"] == "EOS R"
    assert result.payload["json_report_path"] == str(output_json.resolve())


def test_convert_dpx_to_prores_uses_default_output_root(tmp_path: Path, monkeypatch) -> None:
    input_root = tmp_path / "plates"
    input_root.mkdir(parents=True)

    def _fake_convert(
        *,
        input_root: Path,
        output_root: Path | None,
        framerate: int,
        overwrite: bool,
    ) -> list[Path]:
        assert output_root is None
        assert framerate == 24
        assert overwrite is True
        return [input_root / "PRORES" / "SHOT_A.mov"]

    monkeypatch.setattr(app_api, "convert_dpx_sequences_to_prores", _fake_convert)

    result = app_api.convert_dpx_to_prores(input_dir=input_root)
    assert result.input_dir == input_root.resolve()
    assert result.output_dir == (input_root / "PRORES").resolve()
    assert result.outputs == ((input_root / "PRORES" / "SHOT_A.mov").resolve(),)
