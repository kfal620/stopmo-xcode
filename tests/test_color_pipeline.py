from __future__ import annotations

import numpy as np

from stopmo_xcode.color.pipeline import ColorPipeline
from stopmo_xcode.config import PipelineConfig


def test_pipeline_hash_is_stable() -> None:
    cfg = PipelineConfig()
    a = ColorPipeline(cfg).version_hash()
    b = ColorPipeline(cfg).version_hash()
    assert a == b


def test_pipeline_transform_shape() -> None:
    cfg = PipelineConfig()
    pipe = ColorPipeline(cfg)
    img = np.ones((4, 4, 3), dtype=np.float32) * 0.18
    out = pipe.transform(img)
    assert out.shape == img.shape
    assert out.dtype == np.float32
