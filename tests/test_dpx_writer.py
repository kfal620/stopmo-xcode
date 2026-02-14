from __future__ import annotations

from pathlib import Path
import struct

import numpy as np

from stopmo_xcode.write.dpx_writer import write_dpx10_logc_awg


def test_dpx_writer_header_fields(tmp_path: Path) -> None:
    img = np.zeros((2, 3, 3), dtype=np.float32)
    img[..., 0] = 0.1
    img[..., 1] = 0.2
    img[..., 2] = 0.3

    out = tmp_path / "SHOT_A_0001.dpx"
    write_dpx10_logc_awg(out, img)

    data = out.read_bytes()
    assert data[:4] == b"SDPX"

    file_size = struct.unpack_from(">I", data, 16)[0]
    width = struct.unpack_from(">I", data, 772)[0]
    height = struct.unpack_from(">I", data, 776)[0]

    assert file_size == len(data)
    assert width == 3
    assert height == 2
