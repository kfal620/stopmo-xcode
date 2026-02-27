"""Decode protocol and canonical decode exception hierarchy."""

from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .types import DecodedFrame


class DecodeError(RuntimeError):
    """Base error for decode pipeline failures."""

    pass


class UnsupportedFormatError(DecodeError):
    """Raised when no decoder supports the provided source format."""

    pass


class MissingDependencyError(DecodeError):
    """Raised when optional decode dependencies are not installed."""

    pass


class Decoder(Protocol):
    """Protocol implemented by concrete source decoders."""

    def decode(self, path: Path, wb_override: tuple[float, float, float, float] | None = None) -> DecodedFrame:
        ...
