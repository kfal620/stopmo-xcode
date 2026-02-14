from __future__ import annotations

from pathlib import Path

from .base import DecodeError, UnsupportedFormatError
from .libraw_decoder import LibRawDecoder
from .types import DecodedFrame


class DragonframeRawDecoder:
    """Decoder wrapper for Dragonframe .RAW files.

    Dragonframe .RAW files vary by camera backend. We first attempt LibRaw.
    If unsupported, this module fails explicitly so callers can report a clear error.
    """

    def __init__(self) -> None:
        self._libraw = LibRawDecoder()

    def decode(self, path: Path, wb_override: tuple[float, float, float, float] | None = None) -> DecodedFrame:
        try:
            return self._libraw.decode(path=path, wb_override=wb_override)
        except Exception as exc:
            raise UnsupportedFormatError(
                f"Dragonframe .RAW decode is not supported for this file yet: {path}. "
                "If this .RAW is LibRaw-compatible it should decode; otherwise add a dedicated decoder module."
            ) from exc
