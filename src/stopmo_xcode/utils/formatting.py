from __future__ import annotations

from fractions import Fraction


def shutter_seconds_to_fraction(value: float | None, max_denominator: int = 1000000) -> str | None:
    if value is None:
        return None
    if value <= 0:
        return None

    frac = Fraction(value).limit_denominator(max_denominator)
    return f"{frac.numerator}/{frac.denominator}"
