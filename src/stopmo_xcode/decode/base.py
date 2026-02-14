from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .types import DecodedFrame


class DecodeError(RuntimeError):
    pass


class UnsupportedFormatError(DecodeError):
    pass


class MissingDependencyError(DecodeError):
    pass


class Decoder(Protocol):
    def decode(self, path: Path, wb_override: tuple[float, float, float, float] | None = None) -> DecodedFrame:
        ...
