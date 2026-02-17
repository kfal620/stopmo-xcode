from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class WatchConfig:
    source_dir: Path
    working_dir: Path
    output_dir: Path
    db_path: Path
    include_extensions: tuple[str, ...] = (".cr2", ".cr3", ".raw")
    stable_seconds: float = 3.0
    poll_interval_seconds: float = 1.0
    scan_interval_seconds: float = 5.0
    max_workers: int = 2
    shot_complete_seconds: float = 30.0
    shot_regex: str | None = None


@dataclass
class PipelineConfig:
    camera_to_reference_matrix: tuple[tuple[float, float, float], ...] = (
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
    )
    exposure_offset_stops: float = 0.0
    auto_exposure_from_iso: bool = False
    lock_wb_from_first_frame: bool = True
    target_ei: int = 800
    apply_match_lut: bool = False
    match_lut_path: Path | None = None
    use_ocio: bool = False
    ocio_config_path: Path | None = None
    ocio_input_space: str = "camera_linear"
    ocio_reference_space: str = "ACES2065-1"
    ocio_output_space: str = "ARRI_LogC3_EI800_AWG"


@dataclass
class OutputConfig:
    emit_per_frame_json: bool = True
    emit_truth_frame_pack: bool = True
    truth_frame_index: int = 1
    write_debug_tiff: bool = False
    write_prores_on_shot_complete: bool = False
    framerate: int = 24
    show_lut_rec709_path: Path | None = None


@dataclass
class AppConfig:
    watch: WatchConfig
    pipeline: PipelineConfig = field(default_factory=PipelineConfig)
    output: OutputConfig = field(default_factory=OutputConfig)
    log_level: str = "INFO"
    log_file: Path | None = None


def _as_tuple_matrix(raw: list[list[float]]) -> tuple[tuple[float, float, float], ...]:
    if len(raw) != 3 or any(len(row) != 3 for row in raw):
        raise ValueError("camera_to_reference_matrix must be 3x3")
    return tuple(tuple(float(v) for v in row) for row in raw)


def _expand_path(value: str | None, base: Path) -> Path | None:
    if value in (None, ""):
        return None
    path = Path(value)
    if not path.is_absolute():
        path = (base / path).resolve()
    return path


def _require(data: dict[str, Any], key: str) -> Any:
    if key not in data:
        raise ValueError(f"missing required config key: {key}")
    return data[key]


def load_config(path: str | Path) -> AppConfig:
    try:
        import yaml  # type: ignore
    except Exception as exc:
        raise RuntimeError("PyYAML is required for config loading. Install with: pip install PyYAML") from exc

    cfg_path = Path(path).expanduser().resolve()
    with cfg_path.open("r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}

    base = cfg_path.parent
    watch_raw = raw.get("watch", {})
    pipeline_raw = raw.get("pipeline", {})
    output_raw = raw.get("output", {})

    watch = WatchConfig(
        source_dir=_expand_path(_require(watch_raw, "source_dir"), base) or Path("."),
        working_dir=_expand_path(_require(watch_raw, "working_dir"), base) or Path("."),
        output_dir=_expand_path(_require(watch_raw, "output_dir"), base) or Path("."),
        db_path=_expand_path(_require(watch_raw, "db_path"), base) or Path("."),
        include_extensions=tuple(ext.lower() for ext in watch_raw.get("include_extensions", [".cr2", ".cr3", ".raw"])),
        stable_seconds=float(watch_raw.get("stable_seconds", 3.0)),
        poll_interval_seconds=float(watch_raw.get("poll_interval_seconds", 1.0)),
        scan_interval_seconds=float(watch_raw.get("scan_interval_seconds", 5.0)),
        max_workers=int(watch_raw.get("max_workers", 2)),
        shot_complete_seconds=float(watch_raw.get("shot_complete_seconds", 30.0)),
        shot_regex=watch_raw.get("shot_regex"),
    )

    matrix_raw = pipeline_raw.get("camera_to_reference_matrix", [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
    pipeline = PipelineConfig(
        camera_to_reference_matrix=_as_tuple_matrix(matrix_raw),
        exposure_offset_stops=float(pipeline_raw.get("exposure_offset_stops", 0.0)),
        auto_exposure_from_iso=bool(pipeline_raw.get("auto_exposure_from_iso", False)),
        lock_wb_from_first_frame=bool(pipeline_raw.get("lock_wb_from_first_frame", True)),
        target_ei=int(pipeline_raw.get("target_ei", 800)),
        apply_match_lut=bool(pipeline_raw.get("apply_match_lut", False)),
        match_lut_path=_expand_path(pipeline_raw.get("match_lut_path"), base),
        use_ocio=bool(pipeline_raw.get("use_ocio", False)),
        ocio_config_path=_expand_path(pipeline_raw.get("ocio_config_path"), base),
        ocio_input_space=str(pipeline_raw.get("ocio_input_space", "camera_linear")),
        ocio_reference_space=str(pipeline_raw.get("ocio_reference_space", "ACES2065-1")),
        ocio_output_space=str(pipeline_raw.get("ocio_output_space", "ARRI_LogC3_EI800_AWG")),
    )

    output = OutputConfig(
        emit_per_frame_json=bool(output_raw.get("emit_per_frame_json", True)),
        emit_truth_frame_pack=bool(output_raw.get("emit_truth_frame_pack", True)),
        truth_frame_index=int(output_raw.get("truth_frame_index", 1)),
        write_debug_tiff=bool(output_raw.get("write_debug_tiff", False)),
        write_prores_on_shot_complete=bool(output_raw.get("write_prores_on_shot_complete", False)),
        framerate=int(output_raw.get("framerate", 24)),
        show_lut_rec709_path=_expand_path(output_raw.get("show_lut_rec709_path"), base),
    )

    app = AppConfig(
        watch=watch,
        pipeline=pipeline,
        output=output,
        log_level=str(raw.get("log_level", "INFO")),
        log_file=_expand_path(raw.get("log_file"), base),
    )

    ensure_dirs(app)
    return app


def ensure_dirs(config: AppConfig) -> None:
    config.watch.source_dir.mkdir(parents=True, exist_ok=True)
    config.watch.working_dir.mkdir(parents=True, exist_ok=True)
    config.watch.output_dir.mkdir(parents=True, exist_ok=True)
    config.watch.db_path.parent.mkdir(parents=True, exist_ok=True)
    if config.log_file is not None:
        config.log_file.parent.mkdir(parents=True, exist_ok=True)
