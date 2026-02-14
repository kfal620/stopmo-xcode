from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import struct

import numpy as np


HEADER_SIZE = 2048


def _to_ascii_bytes(value: str, length: int) -> bytes:
    b = value.encode("ascii", errors="ignore")[: length - 1]
    return b + b"\x00" * (length - len(b))


def _build_header(
    width: int,
    height: int,
    filename: str,
    file_size: int,
    data_offset: int,
    creator: str,
    project: str,
    description: str,
) -> bytes:
    header = bytearray(HEADER_SIZE)

    struct.pack_into(">4s", header, 0, b"SDPX")
    struct.pack_into(">I", header, 4, data_offset)
    struct.pack_into(">8s", header, 8, _to_ascii_bytes("V2.0", 8))
    struct.pack_into(">I", header, 16, file_size)
    struct.pack_into(">I", header, 20, 0)
    struct.pack_into(">I", header, 24, 1664)
    struct.pack_into(">I", header, 28, 384)
    struct.pack_into(">I", header, 32, 0)

    struct.pack_into(">100s", header, 36, _to_ascii_bytes(filename, 100))
    ts = datetime.now(timezone.utc).strftime("%Y:%m:%d:%H:%M:%S%z")
    struct.pack_into(">24s", header, 136, _to_ascii_bytes(ts, 24))
    struct.pack_into(">100s", header, 160, _to_ascii_bytes(creator, 100))
    struct.pack_into(">200s", header, 260, _to_ascii_bytes(project, 200))
    struct.pack_into(">200s", header, 460, _to_ascii_bytes("", 200))
    struct.pack_into(">I", header, 660, 0xFFFFFFFF)

    struct.pack_into(">H", header, 768, 0)  # orientation
    struct.pack_into(">H", header, 770, 1)  # one image element
    struct.pack_into(">I", header, 772, width)
    struct.pack_into(">I", header, 776, height)

    struct.pack_into(">I", header, 780, 0)  # data sign
    struct.pack_into(">I", header, 784, 0)  # reference low code value
    struct.pack_into(">f", header, 788, 0.0)  # reference low quantity
    struct.pack_into(">I", header, 792, 1023)  # reference high code value
    struct.pack_into(">f", header, 796, 1.0)  # reference high quantity
    struct.pack_into(">B", header, 800, 50)  # descriptor: RGB
    struct.pack_into(">B", header, 801, 2)  # transfer: logarithmic
    struct.pack_into(">B", header, 802, 1)  # colorimetric
    struct.pack_into(">B", header, 803, 10)  # bits per sample
    struct.pack_into(">H", header, 804, 1)  # packing method A
    struct.pack_into(">H", header, 806, 0)  # encoding: none
    struct.pack_into(">I", header, 808, data_offset)
    struct.pack_into(">I", header, 812, 0)
    struct.pack_into(">I", header, 816, 0)
    struct.pack_into(">32s", header, 820, _to_ascii_bytes(description, 32))

    struct.pack_into(">I", header, 1628, 0)  # time code
    struct.pack_into(">I", header, 1632, 0)  # user bits
    return bytes(header)


def _pack_rgb10(image: np.ndarray) -> bytes:
    rgb = np.asarray(image, dtype=np.float32)
    rgb = np.nan_to_num(rgb, nan=0.0, posinf=1.0, neginf=0.0)
    rgb = np.clip(rgb, 0.0, 1.0)

    code = np.rint(rgb * 1023.0).astype(np.uint32)
    r = code[..., 0]
    g = code[..., 1]
    b = code[..., 2]

    words = (r << 22) | (g << 12) | (b << 2)
    return words.astype(">u4", copy=False).tobytes()


def write_dpx10_logc_awg(path: Path, logc_awg_rgb: np.ndarray, creator: str = "stopmo-xcode") -> None:
    if logc_awg_rgb.ndim != 3 or logc_awg_rgb.shape[2] != 3:
        raise ValueError(f"expected HxWx3 RGB image, got {logc_awg_rgb.shape}")

    height, width, _ = logc_awg_rgb.shape
    payload = _pack_rgb10(logc_awg_rgb)
    data_offset = HEADER_SIZE
    file_size = data_offset + len(payload)

    header = _build_header(
        width=width,
        height=height,
        filename=path.name,
        file_size=file_size,
        data_offset=data_offset,
        creator=creator,
        project="stopmo-xcode",
        description="ARRI LogC3 EI800 + AWG",
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(header)
        f.write(payload)
