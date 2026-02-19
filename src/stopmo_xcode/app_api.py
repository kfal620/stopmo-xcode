from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

from stopmo_xcode.assemble import convert_dpx_sequences_to_prores
from stopmo_xcode.color.matrix_suggest import MatrixSuggestion, suggest_camera_to_reference_matrix
from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB
from stopmo_xcode.service import run_watch_service, transcode_one as service_transcode_one
from stopmo_xcode.utils.logging_utils import configure_logging


@dataclass(frozen=True)
class QueueJobStatus:
    id: int
    state: str
    shot: str
    frame: int
    source: str
    attempts: int
    last_error: str | None
    updated_at: str


@dataclass(frozen=True)
class QueueStatus:
    db_path: str
    counts: dict[str, int]
    recent: tuple[QueueJobStatus, ...]


@dataclass(frozen=True)
class MatrixSuggestResult:
    report: MatrixSuggestion
    payload: dict[str, object]
    json_report_path: Path | None


@dataclass(frozen=True)
class DpxToProresResult:
    input_dir: Path
    output_dir: Path
    outputs: tuple[Path, ...]


def run_watch(config_path: str | Path) -> None:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)
    run_watch_service(config)


def run_transcode_one(
    config_path: str | Path,
    input_path: str | Path,
    output_dir: str | Path | None = None,
) -> Path:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)

    resolved_input = Path(input_path).expanduser().resolve()
    resolved_output = Path(output_dir).expanduser().resolve() if output_dir else None
    return service_transcode_one(config, input_path=resolved_input, output_dir=resolved_output)


def get_status(config_path: str | Path, limit: int = 20) -> QueueStatus:
    config = load_config(config_path)
    configure_logging(config.log_level, config.log_file)

    db = QueueDB(config.watch.db_path)
    try:
        counts = db.stats()
        jobs = db.recent_jobs(limit=limit)
        return QueueStatus(
            db_path=str(config.watch.db_path),
            counts=counts,
            recent=tuple(
                QueueJobStatus(
                    id=job.id,
                    state=job.state,
                    shot=job.shot_name,
                    frame=job.frame_number,
                    source=job.source_path,
                    attempts=job.attempts,
                    last_error=job.last_error,
                    updated_at=job.updated_at,
                )
                for job in jobs
            ),
        )
    finally:
        db.close()


def suggest_matrix(
    input_path: str | Path,
    camera_make_override: str | None = None,
    camera_model_override: str | None = None,
    write_json_path: str | Path | None = None,
) -> MatrixSuggestResult:
    resolved_input = Path(input_path).expanduser().resolve()
    report = suggest_camera_to_reference_matrix(
        resolved_input,
        reference_space="ACES2065-1",
        camera_make_override=camera_make_override,
        camera_model_override=camera_model_override,
    )
    payload: dict[str, object] = report.to_json_dict()

    json_path = Path(write_json_path).expanduser().resolve() if write_json_path else None
    if json_path is not None:
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        payload["json_report_path"] = str(json_path)

    return MatrixSuggestResult(report=report, payload=payload, json_report_path=json_path)


def convert_dpx_to_prores(
    input_dir: str | Path,
    output_dir: str | Path | None = None,
    framerate: int = 24,
    overwrite: bool = True,
) -> DpxToProresResult:
    resolved_input = Path(input_dir).expanduser().resolve()
    resolved_output = Path(output_dir).expanduser().resolve() if output_dir else None
    outputs = convert_dpx_sequences_to_prores(
        input_root=resolved_input,
        output_root=resolved_output,
        framerate=int(framerate),
        overwrite=bool(overwrite),
    )
    final_output_dir = (resolved_output or (resolved_input / "PRORES")).resolve()
    return DpxToProresResult(
        input_dir=resolved_input,
        output_dir=final_output_dir,
        outputs=tuple(outputs),
    )
