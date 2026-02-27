"""Formatting helpers shared by metadata and UI/bridge payload generation."""

from __future__ import annotations

from fractions import Fraction


def shutter_seconds_to_fraction(value: float | None, max_denominator: int = 1000000) -> str | None:
    """Render shutter seconds as reduced fraction text for metadata sidecars."""

    if value is None:
        return None
    if value <= 0:
        return None

    frac = Fraction(value).limit_denominator(max_denominator)
    return f"{frac.numerator}/{frac.denominator}"
