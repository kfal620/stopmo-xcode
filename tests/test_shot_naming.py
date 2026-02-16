from __future__ import annotations

from pathlib import Path

from stopmo_xcode.utils.shot import infer_frame_number, infer_shot_name


def test_infer_shot_name_uses_stem_prefix_not_incoming_parent() -> None:
    p = Path('/tmp/incoming/SHOT_A_0012.CR3')
    assert infer_shot_name(p) == 'SHOT_A'


def test_infer_shot_name_falls_back_when_no_numeric_suffix() -> None:
    p = Path('/tmp/incoming/HEROFRAME.CR3')
    assert infer_shot_name(p) == 'HEROFRAME'


def test_infer_frame_number_trailing_digits() -> None:
    p = Path('/tmp/anything/SHOT_A_0012.CR3')
    assert infer_frame_number(p) == 12
