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


def test_pipeline_transform_exposure_override_changes_output() -> None:
    cfg = PipelineConfig(exposure_offset_stops=0.0)
    pipe = ColorPipeline(cfg)
    img = np.ones((2, 2, 3), dtype=np.float32) * 0.18
    base = pipe.transform(img, exposure_offset_stops=0.0)
    boosted = pipe.transform(img, exposure_offset_stops=1.0)
    assert float(np.mean(boosted)) > float(np.mean(base))


def test_pipeline_contrast_keeps_pivot_stable() -> None:
    img = np.ones((2, 2, 3), dtype=np.float32) * 0.18
    a = ColorPipeline(PipelineConfig(contrast=1.0, contrast_pivot_linear=0.18)).transform(img)
    b = ColorPipeline(PipelineConfig(contrast=1.3, contrast_pivot_linear=0.18)).transform(img)
    assert np.allclose(a, b, atol=1e-6)


def test_pipeline_contrast_increases_distance_from_pivot() -> None:
    img = np.array(
        [
            [[0.09, 0.09, 0.09]],
            [[0.36, 0.36, 0.36]],
        ],
        dtype=np.float32,
    )
    pivot_img = np.ones((1, 1, 3), dtype=np.float32) * 0.18

    base_pipe = ColorPipeline(PipelineConfig(contrast=1.0, contrast_pivot_linear=0.18))
    contrast_pipe = ColorPipeline(PipelineConfig(contrast=1.3, contrast_pivot_linear=0.18))

    base = base_pipe.transform(img)
    boosted = contrast_pipe.transform(img)
    pivot = float(base_pipe.transform(pivot_img)[0, 0, 1])

    base_low = abs(float(base[0, 0, 1]) - pivot)
    base_high = abs(float(base[1, 0, 1]) - pivot)
    boosted_low = abs(float(boosted[0, 0, 1]) - pivot)
    boosted_high = abs(float(boosted[1, 0, 1]) - pivot)

    assert boosted_low > base_low
    assert boosted_high > base_high
