from __future__ import annotations

from dataclasses import dataclass
import logging
from pathlib import Path
import shutil
import subprocess
import re


logger = logging.getLogger(__name__)


class AssemblyError(RuntimeError):
    pass


@dataclass
class DpxSequence:
    shot_name: str
    dpx_dir: Path
    raw_prefix: str
    sequence_name: str
    frame_count: int


_TRAILING_FRAME_RE = re.compile(r"^(?P<prefix>.*?)(?P<frame>\d+)$")


def _require_ffmpeg() -> str:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise AssemblyError("ffmpeg not found in PATH; cannot assemble ProRes")
    return ffmpeg


def assemble_logc_prores_4444(
    dpx_glob: str,
    out_mov: Path,
    framerate: int,
) -> None:
    ffmpeg = _require_ffmpeg()
    out_mov.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        ffmpeg,
        "-y",
        "-pattern_type",
        "glob",
        "-framerate",
        str(framerate),
        "-i",
        dpx_glob,
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


def _sequence_parts_from_stem(stem: str) -> tuple[str, str] | None:
    m = _TRAILING_FRAME_RE.match(stem)
    if m is None:
        return None

    raw_prefix = m.group("prefix")
    if raw_prefix == "":
        return None

    sequence_name = raw_prefix.rstrip("_-. ")
    if sequence_name == "":
        sequence_name = raw_prefix
    return raw_prefix, sequence_name


def discover_dpx_sequences(root_dir: Path) -> list[DpxSequence]:
    sequences: list[DpxSequence] = []

    for dpx_dir in sorted(p for p in root_dir.rglob("dpx") if p.is_dir()):
        groups: dict[str, list[Path]] = {}
        for dpx_file in sorted(dpx_dir.glob("*.dpx")):
            parts = _sequence_parts_from_stem(dpx_file.stem)
            if parts is None:
                continue
            raw_prefix, _ = parts
            groups.setdefault(raw_prefix, []).append(dpx_file)

        for raw_prefix, files in sorted(groups.items()):
            parts = _sequence_parts_from_stem(files[0].stem)
            if parts is None:
                continue
            _, sequence_name = parts
            shot_name = dpx_dir.parent.name or "default_shot"
            sequences.append(
                DpxSequence(
                    shot_name=shot_name,
                    dpx_dir=dpx_dir,
                    raw_prefix=raw_prefix,
                    sequence_name=sequence_name,
                    frame_count=len(files),
                )
            )

    return sequences


def convert_dpx_sequences_to_prores(
    input_root: Path,
    output_root: Path | None = None,
    framerate: int = 24,
    overwrite: bool = True,
) -> list[Path]:
    if output_root is None:
        output_root = input_root / "PRORES"

    output_root.mkdir(parents=True, exist_ok=True)
    sequences = discover_dpx_sequences(input_root)
    outputs: list[Path] = []
    reserved_names: dict[str, DpxSequence] = {}

    for seq in sequences:
        out_name = f"{seq.sequence_name}.mov"
        existing = reserved_names.get(out_name)
        if existing is not None and existing.dpx_dir != seq.dpx_dir:
            raise AssemblyError(
                "sequence name collision for flat PRORES output: "
                f"{out_name} from {existing.dpx_dir} and {seq.dpx_dir}. "
                "Rename one sequence prefix or use --out-dir per batch."
            )
        reserved_names[out_name] = seq

        out_mov = output_root / out_name

        if out_mov.exists() and not overwrite:
            logger.info("skip existing %s", out_mov)
            continue

        dpx_glob = str(seq.dpx_dir / f"{seq.raw_prefix}[0-9]*.dpx")
        assemble_logc_prores_4444(
            dpx_glob=dpx_glob,
            out_mov=out_mov,
            framerate=framerate,
        )
        outputs.append(out_mov)
        logger.info(
            "assembled dpx sequence shot=%s seq=%s frames=%s -> %s",
            seq.shot_name,
            seq.sequence_name,
            seq.frame_count,
            out_mov,
        )

    return outputs


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
