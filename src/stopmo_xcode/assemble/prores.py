from __future__ import annotations

import logging
from pathlib import Path
import shutil
import subprocess


logger = logging.getLogger(__name__)


class AssemblyError(RuntimeError):
    pass


def _require_ffmpeg() -> str:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise AssemblyError("ffmpeg not found in PATH; cannot assemble ProRes")
    return ffmpeg


def assemble_logc_prores_4444(
    dpx_pattern: str,
    out_mov: Path,
    framerate: int,
) -> None:
    ffmpeg = _require_ffmpeg()
    out_mov.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        ffmpeg,
        "-y",
        "-framerate",
        str(framerate),
        "-i",
        dpx_pattern,
        "-c:v",
        "prores_ks",
        "-profile:v",
        "4",
        "-pix_fmt",
        "yuva444p10le",
        str(out_mov),
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssemblyError(f"ffmpeg prores assembly failed: {proc.stderr.strip()}")


def assemble_rec709_review(
    in_mov: Path,
    out_mov: Path,
    show_lut_cube: Path,
) -> None:
    ffmpeg = _require_ffmpeg()
    out_mov.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(in_mov),
        "-vf",
        f"lut3d={show_lut_cube}",
        "-c:v",
        "prores_ks",
        "-profile:v",
        "3",
        str(out_mov),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssemblyError(f"ffmpeg review assembly failed: {proc.stderr.strip()}")


def write_handoff_readme(path: Path) -> None:
    text = (
        "STOPMO-XCODE HANDOFF\n"
        "====================\n\n"
        "Primary plates are ARRI LogC3 EI800 + ARRI Wide Gamut (AWG).\n"
        "Do not bake a viewing LUT into plate delivery.\n\n"
        "Viewing in editorial/review:\n"
        "1) Interpret image data as LogC3/AWG.\n"
        "2) Apply show LUT (LogC3/AWG -> Rec709) only for display.\n\n"
        "Wire-removal return should stay in LogC3/AWG for final conform.\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
