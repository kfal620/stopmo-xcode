from __future__ import annotations

from pathlib import Path

from stopmo_xcode.config import load_config


def test_load_config_creates_dirs(tmp_path: Path) -> None:
    cfg_file = tmp_path / "config.yaml"
    cfg_file.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
""",
        encoding="utf-8",
    )

    cfg = load_config(cfg_file)
    assert cfg.watch.source_dir.exists()
    assert cfg.watch.working_dir.exists()
    assert cfg.watch.output_dir.exists()
    assert cfg.watch.db_path.parent.exists()
