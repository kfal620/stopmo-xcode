from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import json
import shutil
import subprocess


@dataclass
class ExifMetadata:
    iso: float | None = None
    shutter_s: float | None = None
    aperture_f: float | None = None


def _ratio_like_to_float(value: Any) -> float | None:
    if value is None:
        return None

    # exifread often stores values as a list-like container.
    if isinstance(value, (list, tuple)) and len(value) > 0:
        value = value[0]

    if hasattr(value, "num") and hasattr(value, "den"):
        den = float(getattr(value, "den", 0) or 0)
        if den == 0.0:
            return None
        return float(getattr(value, "num", 0)) / den

    try:
        return float(value)
    except Exception:
        return None


def _extract_with_exifread(path: Path) -> ExifMetadata:
    try:
        import exifread  # type: ignore
    except Exception:
        return ExifMetadata()

    try:
        with path.open("rb") as f:
            tags = exifread.process_file(f, details=False)
    except Exception:
        return ExifMetadata()

    iso = _ratio_like_to_float(tags.get("EXIF ISOSpeedRatings") or tags.get("EXIF PhotographicSensitivity"))
    shutter = _ratio_like_to_float(tags.get("EXIF ExposureTime"))
    aperture = _ratio_like_to_float(tags.get("EXIF FNumber"))
    if iso is not None and iso <= 0:
        iso = None
    if shutter is not None and shutter <= 0:
        shutter = None
    if aperture is not None and aperture <= 0:
        aperture = None
    return ExifMetadata(iso=iso, shutter_s=shutter, aperture_f=aperture)


def _extract_with_exiftool(path: Path) -> ExifMetadata:
    exiftool = shutil.which("exiftool")
    if exiftool is None:
        return ExifMetadata()

    try:
        proc = subprocess.run(
            [
                exiftool,
                "-j",
                "-n",
                "-ISO",
                "-ExposureTime",
                "-FNumber",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            return ExifMetadata()

        rows = json.loads(proc.stdout)
        if not rows:
            return ExifMetadata()
        row = rows[0]

        iso = _ratio_like_to_float(row.get("ISO"))
        shutter = _ratio_like_to_float(row.get("ExposureTime"))
        aperture = _ratio_like_to_float(row.get("FNumber"))
        if iso is not None and iso <= 0:
            iso = None
        if shutter is not None and shutter <= 0:
            shutter = None
        if aperture is not None and aperture <= 0:
            aperture = None
        return ExifMetadata(iso=iso, shutter_s=shutter, aperture_f=aperture)
    except Exception:
        return ExifMetadata()


def extract_exif_metadata(path: Path) -> ExifMetadata:
    """Extract ISO/shutter/aperture from RAW file metadata.

    Preference order:
    1) Python exifread (lightweight, in-process)
    2) exiftool CLI (if installed)
    """

    # exifread does not reliably handle ISO BMFF RAW containers such as .CR3.
    # Use it only for TIFF-based RAW families where it is stable.
    if path.suffix.lower() in {".cr2", ".dng", ".nef", ".arw", ".rw2", ".orf"}:
        md = _extract_with_exifread(path)
        if md.iso is not None or md.shutter_s is not None or md.aperture_f is not None:
            return md

    md_tool = _extract_with_exiftool(path)
    if md_tool.iso is not None or md_tool.shutter_s is not None or md_tool.aperture_f is not None:
        return md_tool

    return ExifMetadata()
