from __future__ import annotations

from pathlib import Path

from stopmo_xcode.assemble import prores


def test_discover_dpx_sequences_uses_only_dpx_dirs(tmp_path: Path) -> None:
    dpx1 = tmp_path / "SHOT_A" / "dpx"
    dpx1.mkdir(parents=True)
    (dpx1 / "PAW_0001.dpx").write_bytes(b"")
    (dpx1 / "PAW_0002.dpx").write_bytes(b"")

    dpx2 = tmp_path / "SHOT_B" / "dpx"
    dpx2.mkdir(parents=True)
    (dpx2 / "CAT-0001.dpx").write_bytes(b"")

    truth = tmp_path / "SHOT_A" / "truth_frame"
    truth.mkdir(parents=True)
    (truth / "PAW_0001_truth_logc_awg.dpx").write_bytes(b"")

    seqs = prores.discover_dpx_sequences(tmp_path)

    assert len(seqs) == 2
    by_name = {s.sequence_name: s for s in seqs}
    assert set(by_name) == {"PAW", "CAT"}
    assert by_name["PAW"].shot_name == "SHOT_A"
    assert by_name["PAW"].frame_count == 2
    assert by_name["CAT"].shot_name == "SHOT_B"
    assert by_name["CAT"].frame_count == 1


def test_convert_dpx_sequences_to_prores_outputs_to_default_prores(tmp_path: Path, monkeypatch) -> None:
    dpx = tmp_path / "SHOT_A" / "dpx"
    dpx.mkdir(parents=True)
    (dpx / "PAW_0001.dpx").write_bytes(b"")
    (dpx / "PAW_0002.dpx").write_bytes(b"")

    calls: list[tuple[str, Path, int]] = []

    def _fake_assemble(dpx_glob: str, out_mov: Path, framerate: int) -> None:
        calls.append((dpx_glob, out_mov, framerate))
        out_mov.parent.mkdir(parents=True, exist_ok=True)
        out_mov.write_bytes(b"fake")

    monkeypatch.setattr(prores, "assemble_logc_prores_4444", _fake_assemble)

    out = prores.convert_dpx_sequences_to_prores(tmp_path, output_root=None, framerate=24, overwrite=True)

    assert len(out) == 1
    expected = tmp_path / "PRORES" / "PAW.mov"
    assert out[0] == expected
    assert expected.exists()

    assert len(calls) == 1
    dpx_glob, out_mov, fps = calls[0]
    assert dpx_glob.endswith("/SHOT_A/dpx/PAW_[0-9]*.dpx")
    assert out_mov == expected
    assert fps == 24


def test_convert_dpx_sequences_to_prores_raises_on_flat_name_collision(tmp_path: Path, monkeypatch) -> None:
    dpx1 = tmp_path / "SHOT_A" / "dpx"
    dpx1.mkdir(parents=True)
    (dpx1 / "DUP_0001.dpx").write_bytes(b"")

    dpx2 = tmp_path / "SHOT_B" / "dpx"
    dpx2.mkdir(parents=True)
    (dpx2 / "DUP_0001.dpx").write_bytes(b"")

    monkeypatch.setattr(prores, "assemble_logc_prores_4444", lambda **_: None)

    try:
        prores.convert_dpx_sequences_to_prores(tmp_path, output_root=None, framerate=24, overwrite=True)
        assert False, "expected name collision error"
    except prores.AssemblyError as exc:
        assert "sequence name collision" in str(exc)
