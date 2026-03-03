from __future__ import annotations

from stopmo_xcode import cli


def test_warn_if_legacy_entrypoint_emits_deprecation(capsys) -> None:
    cli._warn_if_legacy_entrypoint("stopmo-xcode")
    captured = capsys.readouterr()
    assert "deprecated" in captured.err
    assert "framerelay" in captured.err


def test_warn_if_legacy_entrypoint_is_silent_for_new_name(capsys) -> None:
    cli._warn_if_legacy_entrypoint("framerelay")
    captured = capsys.readouterr()
    assert captured.err == ""
