"""Public decode registry/types and canonical decode error classes."""

from .base import DecodeError, MissingDependencyError, UnsupportedFormatError
from .registry import DecoderRegistry
from .types import DecodedFrame, RawMetadata

__all__ = [
    "DecodeError",
    "MissingDependencyError",
    "UnsupportedFormatError",
    "DecoderRegistry",
    "DecodedFrame",
    "RawMetadata",
]
