"""Decoder dispatch registry keyed by source file extension."""

from __future__ import annotations

from pathlib import Path

from .base import UnsupportedFormatError
from .dragonframe_raw_decoder import DragonframeRawDecoder
from .libraw_decoder import LibRawDecoder
from .types import DecodedFrame


class DecoderRegistry:
    """Route supported file types to their concrete decoder implementation."""

    def __init__(self) -> None:
        """Initialize decoder instances for currently supported camera formats."""

        self._cr_decoder = LibRawDecoder()
        self._dragon_decoder = DragonframeRawDecoder()

    def decode(self, path: Path, wb_override: tuple[float, float, float, float] | None = None) -> DecodedFrame:
        """Decode one source path using extension-based decoder selection."""

        ext = path.suffix.lower()
        if ext in {".cr2", ".cr3"}:
            return self._cr_decoder.decode(path, wb_override=wb_override)
        if ext == ".raw":
            return self._dragon_decoder.decode(path, wb_override=wb_override)
        raise UnsupportedFormatError(f"unsupported extension {ext} for {path}")
