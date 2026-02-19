from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import time
from typing import Any

from stopmo_xcode import app_api
from stopmo_xcode.config import AppConfig, OutputConfig, PipelineConfig, WatchConfig, load_config
from stopmo_xcode.queue import QueueDB


def _cfg_to_dict(config: AppConfig) -> dict[str, object]:
    return {
        "watch": {
            "source_dir": str(config.watch.source_dir),
            "working_dir": str(config.watch.working_dir),
            "output_dir": str(config.watch.output_dir),
            "db_path": str(config.watch.db_path),
            "include_extensions": list(config.watch.include_extensions),
            "stable_seconds": float(config.watch.stable_seconds),
            "poll_interval_seconds": float(config.watch.poll_interval_seconds),
            "scan_interval_seconds": float(config.watch.scan_interval_seconds),
            "max_workers": int(config.watch.max_workers),
            "shot_complete_seconds": float(config.watch.shot_complete_seconds),
            "shot_regex": config.watch.shot_regex,
        },
        "pipeline": {
            "camera_to_reference_matrix": [[float(v) for v in row] for row in config.pipeline.camera_to_reference_matrix],
            "exposure_offset_stops": float(config.pipeline.exposure_offset_stops),
            "auto_exposure_from_iso": bool(config.pipeline.auto_exposure_from_iso),
            "auto_exposure_from_shutter": bool(config.pipeline.auto_exposure_from_shutter),
            "target_shutter_s": (
                float(config.pipeline.target_shutter_s) if config.pipeline.target_shutter_s is not None else None
            ),
            "auto_exposure_from_aperture": bool(config.pipeline.auto_exposure_from_aperture),
            "target_aperture_f": (
                float(config.pipeline.target_aperture_f) if config.pipeline.target_aperture_f is not None else None
            ),
            "contrast": float(config.pipeline.contrast),
            "contrast_pivot_linear": float(config.pipeline.contrast_pivot_linear),
            "lock_wb_from_first_frame": bool(config.pipeline.lock_wb_from_first_frame),
            "target_ei": int(config.pipeline.target_ei),
            "apply_match_lut": bool(config.pipeline.apply_match_lut),
            "match_lut_path": str(config.pipeline.match_lut_path) if config.pipeline.match_lut_path else None,
            "use_ocio": bool(config.pipeline.use_ocio),
            "ocio_config_path": str(config.pipeline.ocio_config_path) if config.pipeline.ocio_config_path else None,
            "ocio_input_space": str(config.pipeline.ocio_input_space),
            "ocio_reference_space": str(config.pipeline.ocio_reference_space),
            "ocio_output_space": str(config.pipeline.ocio_output_space),
        },
        "output": {
            "emit_per_frame_json": bool(config.output.emit_per_frame_json),
            "emit_truth_frame_pack": bool(config.output.emit_truth_frame_pack),
            "truth_frame_index": int(config.output.truth_frame_index),
            "write_debug_tiff": bool(config.output.write_debug_tiff),
            "write_prores_on_shot_complete": bool(config.output.write_prores_on_shot_complete),
            "framerate": int(config.output.framerate),
            "show_lut_rec709_path": str(config.output.show_lut_rec709_path) if config.output.show_lut_rec709_path else None,
        },
        "log_level": str(config.log_level),
        "log_file": str(config.log_file) if config.log_file else None,
    }


def _read_json_stdin() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        raise ValueError("expected JSON payload on stdin")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("stdin JSON payload must be an object")
    return payload


def _pick(data: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in data:
            return data[key]
    raise KeyError(keys[0])


def _optional(data: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in data:
            return data[key]
    return default


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        text = value.strip().lower()
        if text in {"1", "true", "yes", "on"}:
            return True
        if text in {"0", "false", "no", "off", ""}:
            return False
    raise ValueError(f"cannot parse boolean from value: {value!r}")


def _to_path(value: Any) -> Path:
    if value in (None, ""):
        raise ValueError("required path value is missing")
    return Path(str(value)).expanduser().resolve()


def _to_optional_path(value: Any) -> Path | None:
    if value in (None, ""):
        return None
    return Path(str(value)).expanduser().resolve()


def _to_float(value: Any, *, default: float | None = None) -> float:
    if value in (None, ""):
        if default is not None:
            return float(default)
        raise ValueError("required numeric value is missing")
    return float(value)


def _to_optional_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def _to_int(value: Any, *, default: int | None = None) -> int:
    if value in (None, ""):
        if default is not None:
            return int(default)
        raise ValueError("required integer value is missing")
    return int(value)


def _to_matrix(raw: Any) -> tuple[tuple[float, float, float], ...]:
    if not isinstance(raw, list) or len(raw) != 3:
        raise ValueError("camera_to_reference_matrix must be a 3x3 list")
    out: list[tuple[float, float, float]] = []
    for row in raw:
        if not isinstance(row, list) or len(row) != 3:
            raise ValueError("camera_to_reference_matrix must be a 3x3 list")
        out.append((float(row[0]), float(row[1]), float(row[2])))
    return (out[0], out[1], out[2])


def _payload_to_config(payload: dict[str, Any]) -> AppConfig:
    watch_raw = _pick(payload, "watch")
    pipeline_raw = _pick(payload, "pipeline")
    output_raw = _pick(payload, "output")
    if not isinstance(watch_raw, dict) or not isinstance(pipeline_raw, dict) or not isinstance(output_raw, dict):
        raise ValueError("watch/pipeline/output must be objects")

    include_ext = _optional(watch_raw, "include_extensions", "includeExtensions", default=[".cr2", ".cr3", ".raw"])
    if isinstance(include_ext, str):
        include_ext = [s.strip() for s in include_ext.split(",") if s.strip()]
    if not isinstance(include_ext, list):
        raise ValueError("watch.include_extensions must be a list or comma string")

    watch = WatchConfig(
        source_dir=_to_path(_pick(watch_raw, "source_dir", "sourceDir")),
        working_dir=_to_path(_pick(watch_raw, "working_dir", "workingDir")),
        output_dir=_to_path(_pick(watch_raw, "output_dir", "outputDir")),
        db_path=_to_path(_pick(watch_raw, "db_path", "dbPath")),
        include_extensions=tuple(str(v).lower() for v in include_ext),
        stable_seconds=_to_float(_optional(watch_raw, "stable_seconds", "stableSeconds", default=3.0), default=3.0),
        poll_interval_seconds=_to_float(
            _optional(watch_raw, "poll_interval_seconds", "pollIntervalSeconds", default=1.0),
            default=1.0,
        ),
        scan_interval_seconds=_to_float(
            _optional(watch_raw, "scan_interval_seconds", "scanIntervalSeconds", default=5.0),
            default=5.0,
        ),
        max_workers=_to_int(_optional(watch_raw, "max_workers", "maxWorkers", default=2), default=2),
        shot_complete_seconds=_to_float(
            _optional(watch_raw, "shot_complete_seconds", "shotCompleteSeconds", default=30.0),
            default=30.0,
        ),
        shot_regex=_optional(watch_raw, "shot_regex", "shotRegex", default=None),
    )

    pipeline = PipelineConfig(
        camera_to_reference_matrix=_to_matrix(
            _optional(
                pipeline_raw,
                "camera_to_reference_matrix",
                "cameraToReferenceMatrix",
                default=[[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
            )
        ),
        exposure_offset_stops=_to_float(
            _optional(pipeline_raw, "exposure_offset_stops", "exposureOffsetStops", default=0.0),
            default=0.0,
        ),
        auto_exposure_from_iso=_to_bool(
            _optional(pipeline_raw, "auto_exposure_from_iso", "autoExposureFromIso", default=False)
        ),
        auto_exposure_from_shutter=_to_bool(
            _optional(pipeline_raw, "auto_exposure_from_shutter", "autoExposureFromShutter", default=False)
        ),
        target_shutter_s=_to_optional_float(_optional(pipeline_raw, "target_shutter_s", "targetShutterS", default=None)),
        auto_exposure_from_aperture=_to_bool(
            _optional(pipeline_raw, "auto_exposure_from_aperture", "autoExposureFromAperture", default=False)
        ),
        target_aperture_f=_to_optional_float(
            _optional(pipeline_raw, "target_aperture_f", "targetApertureF", default=None)
        ),
        contrast=_to_float(_optional(pipeline_raw, "contrast", default=1.0), default=1.0),
        contrast_pivot_linear=_to_float(
            _optional(pipeline_raw, "contrast_pivot_linear", "contrastPivotLinear", default=0.18),
            default=0.18,
        ),
        lock_wb_from_first_frame=_to_bool(
            _optional(pipeline_raw, "lock_wb_from_first_frame", "lockWbFromFirstFrame", default=True)
        ),
        target_ei=_to_int(_optional(pipeline_raw, "target_ei", "targetEi", default=800), default=800),
        apply_match_lut=_to_bool(_optional(pipeline_raw, "apply_match_lut", "applyMatchLut", default=False)),
        match_lut_path=_to_optional_path(_optional(pipeline_raw, "match_lut_path", "matchLutPath", default=None)),
        use_ocio=_to_bool(_optional(pipeline_raw, "use_ocio", "useOcio", default=False)),
        ocio_config_path=_to_optional_path(_optional(pipeline_raw, "ocio_config_path", "ocioConfigPath", default=None)),
        ocio_input_space=str(_optional(pipeline_raw, "ocio_input_space", "ocioInputSpace", default="camera_linear")),
        ocio_reference_space=str(
            _optional(pipeline_raw, "ocio_reference_space", "ocioReferenceSpace", default="ACES2065-1")
        ),
        ocio_output_space=str(
            _optional(pipeline_raw, "ocio_output_space", "ocioOutputSpace", default="ARRI_LogC3_EI800_AWG")
        ),
    )

    output = OutputConfig(
        emit_per_frame_json=_to_bool(_optional(output_raw, "emit_per_frame_json", "emitPerFrameJson", default=True)),
        emit_truth_frame_pack=_to_bool(
            _optional(output_raw, "emit_truth_frame_pack", "emitTruthFramePack", default=True)
        ),
        truth_frame_index=_to_int(_optional(output_raw, "truth_frame_index", "truthFrameIndex", default=1), default=1),
        write_debug_tiff=_to_bool(_optional(output_raw, "write_debug_tiff", "writeDebugTiff", default=False)),
        write_prores_on_shot_complete=_to_bool(
            _optional(output_raw, "write_prores_on_shot_complete", "writeProresOnShotComplete", default=False)
        ),
        framerate=_to_int(_optional(output_raw, "framerate", default=24), default=24),
        show_lut_rec709_path=_to_optional_path(
            _optional(output_raw, "show_lut_rec709_path", "showLutRec709Path", default=None)
        ),
    )

    return AppConfig(
        watch=watch,
        pipeline=pipeline,
        output=output,
        log_level=str(_optional(payload, "log_level", "logLevel", default="INFO")),
        log_file=_to_optional_path(_optional(payload, "log_file", "logFile", default=None)),
    )


def _config_to_yaml_payload(config: AppConfig) -> dict[str, object]:
    return {
        "watch": {
            "source_dir": str(config.watch.source_dir),
            "working_dir": str(config.watch.working_dir),
            "output_dir": str(config.watch.output_dir),
            "db_path": str(config.watch.db_path),
            "include_extensions": list(config.watch.include_extensions),
            "stable_seconds": float(config.watch.stable_seconds),
            "poll_interval_seconds": float(config.watch.poll_interval_seconds),
            "scan_interval_seconds": float(config.watch.scan_interval_seconds),
            "max_workers": int(config.watch.max_workers),
            "shot_complete_seconds": float(config.watch.shot_complete_seconds),
            "shot_regex": config.watch.shot_regex,
        },
        "pipeline": {
            "camera_to_reference_matrix": [[float(v) for v in row] for row in config.pipeline.camera_to_reference_matrix],
            "exposure_offset_stops": float(config.pipeline.exposure_offset_stops),
            "auto_exposure_from_iso": bool(config.pipeline.auto_exposure_from_iso),
            "auto_exposure_from_shutter": bool(config.pipeline.auto_exposure_from_shutter),
            "target_shutter_s": config.pipeline.target_shutter_s,
            "auto_exposure_from_aperture": bool(config.pipeline.auto_exposure_from_aperture),
            "target_aperture_f": config.pipeline.target_aperture_f,
            "contrast": float(config.pipeline.contrast),
            "contrast_pivot_linear": float(config.pipeline.contrast_pivot_linear),
            "lock_wb_from_first_frame": bool(config.pipeline.lock_wb_from_first_frame),
            "target_ei": int(config.pipeline.target_ei),
            "apply_match_lut": bool(config.pipeline.apply_match_lut),
            "match_lut_path": str(config.pipeline.match_lut_path) if config.pipeline.match_lut_path else None,
            "use_ocio": bool(config.pipeline.use_ocio),
            "ocio_config_path": str(config.pipeline.ocio_config_path) if config.pipeline.ocio_config_path else None,
            "ocio_input_space": str(config.pipeline.ocio_input_space),
            "ocio_reference_space": str(config.pipeline.ocio_reference_space),
            "ocio_output_space": str(config.pipeline.ocio_output_space),
        },
        "output": {
            "emit_per_frame_json": bool(config.output.emit_per_frame_json),
            "emit_truth_frame_pack": bool(config.output.emit_truth_frame_pack),
            "truth_frame_index": int(config.output.truth_frame_index),
            "write_debug_tiff": bool(config.output.write_debug_tiff),
            "write_prores_on_shot_complete": bool(config.output.write_prores_on_shot_complete),
            "framerate": int(config.output.framerate),
            "show_lut_rec709_path": str(config.output.show_lut_rec709_path) if config.output.show_lut_rec709_path else None,
        },
        "log_level": str(config.log_level),
        "log_file": str(config.log_file) if config.log_file else None,
    }


def read_config_payload(config_path: str | Path) -> dict[str, object]:
    cfg = load_config(config_path)
    payload = _cfg_to_dict(cfg)
    payload["config_path"] = str(Path(config_path).expanduser().resolve())
    return payload


def write_config_payload(config_path: str | Path, payload: dict[str, Any]) -> dict[str, object]:
    try:
        import yaml  # type: ignore
    except Exception as exc:
        raise RuntimeError("PyYAML is required for config writes. Install with: pip install PyYAML") from exc

    config = _payload_to_config(payload)
    out_path = Path(config_path).expanduser().resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    yaml_payload = _config_to_yaml_payload(config)
    out_path.write_text(yaml.safe_dump(yaml_payload, sort_keys=False), encoding="utf-8")

    reloaded = load_config(out_path)
    return {
        "config_path": str(out_path),
        "saved": True,
        "resolved": _cfg_to_dict(reloaded),
    }


def health_payload(config_path: str | Path | None = None) -> dict[str, object]:
    venv_python = Path.cwd() / ".venv" / "bin" / "python"
    ffmpeg_env = os.environ.get("STOPMO_XCODE_FFMPEG")
    ffmpeg_path = ffmpeg_env or shutil.which("ffmpeg")

    checks = {
        "rawpy": importlib.util.find_spec("rawpy") is not None,
        "PyOpenColorIO": importlib.util.find_spec("PyOpenColorIO") is not None,
        "tifffile": importlib.util.find_spec("tifffile") is not None,
        "exifread": importlib.util.find_spec("exifread") is not None,
        "imageio_ffmpeg": importlib.util.find_spec("imageio_ffmpeg") is not None,
        "ffmpeg": ffmpeg_path is not None,
        "exiftool": shutil.which("exiftool") is not None,
    }

    payload: dict[str, object] = {
        "python_executable": sys.executable,
        "python_version": sys.version.split()[0],
        "venv_python": str(venv_python),
        "venv_python_exists": venv_python.exists(),
        "checks": checks,
        "ffmpeg_path": ffmpeg_path,
        "stopmo_version": None,
    }

    try:
        from stopmo_xcode import __version__

        payload["stopmo_version"] = __version__
    except Exception:
        payload["stopmo_version"] = None

    if config_path is not None:
        cfg_path = Path(config_path).expanduser().resolve()
        payload["config_path"] = str(cfg_path)
        payload["config_exists"] = cfg_path.exists()
        if cfg_path.exists():
            try:
                cfg = load_config(cfg_path)
                payload["config_load_ok"] = True
                payload["watch_db_path"] = str(cfg.watch.db_path)
            except Exception as exc:
                payload["config_load_ok"] = False
                payload["config_error"] = str(exc)
    return payload


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _queue_status_from_config(config_path: str | Path, limit: int = 200) -> dict[str, object]:
    cfg = load_config(config_path)
    db = QueueDB(cfg.watch.db_path)
    try:
        counts = db.stats()
        jobs = db.recent_jobs(limit=max(1, int(limit)))
        return {
            "db_path": str(cfg.watch.db_path),
            "counts": counts,
            "total": int(sum(counts.values())),
            "recent": [
                {
                    "id": int(job.id),
                    "state": str(job.state),
                    "shot": str(job.shot_name),
                    "frame": int(job.frame_number),
                    "source": str(job.source_path),
                    "attempts": int(job.attempts),
                    "last_error": job.last_error,
                    "worker_id": job.worker_id,
                    "detected_at": str(job.detected_at),
                    "updated_at": str(job.updated_at),
                }
                for job in jobs
            ],
        }
    finally:
        db.close()


def queue_status_payload(config_path: str | Path, limit: int = 200) -> dict[str, object]:
    return _queue_status_from_config(config_path=config_path, limit=limit)


def shots_summary_payload(config_path: str | Path, limit: int = 500) -> dict[str, object]:
    cfg = load_config(config_path)
    conn = sqlite3.connect(str(cfg.watch.db_path), timeout=30, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            SELECT
                j.shot_name AS shot_name,
                COUNT(*) AS total_frames,
                SUM(CASE WHEN j.state = 'done' THEN 1 ELSE 0 END) AS done_frames,
                SUM(CASE WHEN j.state = 'failed' THEN 1 ELSE 0 END) AS failed_frames,
                SUM(CASE WHEN j.state IN ('detected', 'decoding', 'xform', 'dpx_write') THEN 1 ELSE 0 END) AS inflight_frames,
                MAX(j.updated_at) AS last_updated_at,
                sa.assembly_state AS assembly_state,
                sa.output_mov_path AS output_mov_path,
                sa.review_mov_path AS review_mov_path,
                ss.exposure_offset_stops AS exposure_offset_stops,
                ss.wb_multipliers_json AS wb_multipliers_json
            FROM jobs j
            LEFT JOIN shot_assembly sa ON sa.shot_name = j.shot_name
            LEFT JOIN shot_settings ss ON ss.shot_name = j.shot_name
            GROUP BY j.shot_name
            ORDER BY last_updated_at DESC
            LIMIT ?
            """,
            (max(1, int(limit)),),
        ).fetchall()

        shots: list[dict[str, object]] = []
        for row in rows:
            total = int(row["total_frames"] or 0)
            done = int(row["done_frames"] or 0)
            failed = int(row["failed_frames"] or 0)
            inflight = int(row["inflight_frames"] or 0)
            wb_json = row["wb_multipliers_json"]
            wb_multipliers = json.loads(wb_json) if wb_json else None
            state = "queued"
            if failed > 0:
                state = "issues"
            elif inflight > 0:
                state = "processing"
            elif total > 0 and (done + failed) >= total:
                state = "done"

            progress_ratio = float(done + failed) / float(total) if total > 0 else 0.0
            shots.append(
                {
                    "shot_name": str(row["shot_name"]),
                    "state": state,
                    "total_frames": total,
                    "done_frames": done,
                    "failed_frames": failed,
                    "inflight_frames": inflight,
                    "progress_ratio": progress_ratio,
                    "last_updated_at": row["last_updated_at"],
                    "assembly_state": row["assembly_state"],
                    "output_mov_path": row["output_mov_path"],
                    "review_mov_path": row["review_mov_path"],
                    "exposure_offset_stops": float(row["exposure_offset_stops"])
                    if row["exposure_offset_stops"] is not None
                    else None,
                    "wb_multipliers": wb_multipliers,
                }
            )

        return {
            "db_path": str(cfg.watch.db_path),
            "count": len(shots),
            "shots": shots,
        }
    finally:
        conn.close()


def _watch_state_file(config_path: str | Path) -> Path:
    cfg = load_config(config_path)
    return cfg.watch.working_dir / ".stopmo_gui_watch.json"


def _read_watch_state(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(raw, dict):
        return None
    return raw


def _write_watch_state(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _is_pid_running(pid: int | None) -> bool:
    if pid is None or pid <= 0:
        return False
    try:
        os.kill(int(pid), 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _tail_lines(path: Path | None, max_lines: int = 40) -> list[str]:
    if path is None or not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return []
    if max_lines <= 0:
        return []
    return lines[-max_lines:]


_LOG_LINE_RE = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2},\d+)\s+"
    r"(?P<severity>[A-Z]+)\s+"
    r"(?P<logger>[^\s]+)\s*"
    r"(?P<message>.*)$"
)


def _parse_log_lines(lines: list[str], severity_filter: set[str] | None = None) -> list[dict[str, object]]:
    out: list[dict[str, object]] = []
    for line in lines:
        m = _LOG_LINE_RE.match(line)
        if m is None:
            entry = {
                "timestamp": None,
                "severity": "INFO",
                "logger": "raw",
                "message": line,
                "raw": line,
            }
            sev = "INFO"
        else:
            sev = m.group("severity").upper()
            entry = {
                "timestamp": m.group("timestamp"),
                "severity": sev,
                "logger": m.group("logger"),
                "message": m.group("message"),
                "raw": line,
            }
        if severity_filter is not None and sev not in severity_filter:
            continue
        out.append(entry)
    return out


def _collect_diagnostic_warnings(log_entries: list[dict[str, object]]) -> list[dict[str, object]]:
    warnings: list[dict[str, object]] = []
    patterns: tuple[tuple[str, str], ...] = (
        ("clipping", "high pre-log clipping ratio"),
        ("nan_inf", "non-finite values detected"),
        ("wb_drift", "as-shot WB drift detected"),
        ("dependency_error", "missing dependency"),
        ("decode_failure", "decode failed"),
    )
    for entry in log_entries:
        message = str(entry.get("message", ""))
        lowered = message.lower()
        for code, pattern in patterns:
            if pattern.lower() in lowered:
                warnings.append(
                    {
                        "code": code,
                        "severity": str(entry.get("severity", "WARNING")),
                        "timestamp": entry.get("timestamp"),
                        "message": message,
                        "logger": entry.get("logger"),
                    }
                )
                break
    return warnings


def _read_log_lines(log_path: Path, limit: int = 400) -> list[str]:
    if not log_path.exists():
        return []
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return []
    return lines[-max(1, int(limit)) :]


def _load_cfg_for_path(config_path: str | Path) -> tuple[Path, AppConfig]:
    cfg_path = Path(config_path).expanduser().resolve()
    cfg = load_config(cfg_path)
    return cfg_path, cfg


def _runtime_state_file(config_path: str | Path) -> Path:
    cfg = load_config(config_path)
    return cfg.watch.working_dir / ".stopmo_runtime_state.json"


def _read_runtime_state(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if not isinstance(raw, dict):
        return {}
    return raw


def validate_config_payload(config_path: str | Path) -> dict[str, object]:
    cfg_path, cfg = _load_cfg_for_path(config_path)
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []

    def add_error(code: str, message: str, field: str) -> None:
        errors.append({"code": code, "message": message, "field": field})

    def add_warning(code: str, message: str, field: str) -> None:
        warnings.append({"code": code, "message": message, "field": field})

    if cfg.watch.stable_seconds <= 0:
        add_error("stable_seconds_invalid", "stable_seconds must be > 0", "watch.stable_seconds")
    if cfg.watch.poll_interval_seconds <= 0:
        add_error("poll_interval_invalid", "poll_interval_seconds must be > 0", "watch.poll_interval_seconds")
    if cfg.watch.scan_interval_seconds <= 0:
        add_error("scan_interval_invalid", "scan_interval_seconds must be > 0", "watch.scan_interval_seconds")
    if cfg.watch.max_workers < 1:
        add_error("max_workers_invalid", "max_workers must be >= 1", "watch.max_workers")
    if cfg.watch.shot_complete_seconds < 0:
        add_error("shot_complete_invalid", "shot_complete_seconds must be >= 0", "watch.shot_complete_seconds")
    if cfg.output.framerate <= 0:
        add_error("framerate_invalid", "framerate must be > 0", "output.framerate")
    if cfg.output.truth_frame_index < 1:
        add_error("truth_frame_index_invalid", "truth_frame_index must be >= 1", "output.truth_frame_index")

    if not cfg.watch.include_extensions:
        add_error("extensions_empty", "include_extensions cannot be empty", "watch.include_extensions")
    else:
        for ext in cfg.watch.include_extensions:
            if not str(ext).startswith("."):
                add_warning(
                    "extension_format",
                    f"Extension '{ext}' does not start with '.'; matching may fail",
                    "watch.include_extensions",
                )

    if cfg.watch.shot_regex:
        try:
            re.compile(cfg.watch.shot_regex)
        except re.error as exc:
            add_error("shot_regex_invalid", f"shot_regex is invalid: {exc}", "watch.shot_regex")

    if cfg.pipeline.use_ocio and not cfg.pipeline.ocio_config_path:
        add_error("ocio_missing_config", "use_ocio enabled but ocio_config_path is not set", "pipeline.ocio_config_path")
    if cfg.pipeline.use_ocio and cfg.pipeline.ocio_config_path and not cfg.pipeline.ocio_config_path.exists():
        add_error(
            "ocio_config_not_found",
            f"OCIO config not found: {cfg.pipeline.ocio_config_path}",
            "pipeline.ocio_config_path",
        )
    if cfg.pipeline.apply_match_lut and not cfg.pipeline.match_lut_path:
        add_error("match_lut_missing", "apply_match_lut enabled but match_lut_path is not set", "pipeline.match_lut_path")
    if cfg.pipeline.match_lut_path and not cfg.pipeline.match_lut_path.exists():
        add_error(
            "match_lut_not_found",
            f"Match LUT not found: {cfg.pipeline.match_lut_path}",
            "pipeline.match_lut_path",
        )
    if cfg.output.show_lut_rec709_path and not cfg.output.show_lut_rec709_path.exists():
        add_error(
            "show_lut_not_found",
            f"Show LUT path not found: {cfg.output.show_lut_rec709_path}",
            "output.show_lut_rec709_path",
        )

    for field_name, path in (
        ("watch.source_dir", cfg.watch.source_dir),
        ("watch.working_dir", cfg.watch.working_dir),
        ("watch.output_dir", cfg.watch.output_dir),
        ("watch.db_path.parent", cfg.watch.db_path.parent),
    ):
        if not path.exists():
            add_error("path_missing", f"Path does not exist: {path}", field_name)
            continue
        if not path.is_dir():
            add_error("path_not_dir", f"Path is not a directory: {path}", field_name)
            continue
        if not os.access(path, os.R_OK | os.W_OK | os.X_OK):
            add_error("path_permissions", f"Path is not read/write/executable: {path}", field_name)

    if cfg.watch.source_dir == cfg.watch.output_dir:
        add_warning(
            "source_output_same",
            "source_dir and output_dir are the same directory; this can cause recursive processing confusion",
            "watch.output_dir",
        )
    if str(cfg.watch.output_dir).startswith(str(cfg.watch.source_dir)):
        add_warning(
            "output_inside_source",
            "output_dir is inside source_dir; output files may be re-scanned if extensions overlap",
            "watch.output_dir",
        )

    return {
        "config_path": str(cfg_path),
        "ok": len(errors) == 0,
        "errors": errors,
        "warnings": warnings,
    }


def watch_preflight_payload(config_path: str | Path) -> dict[str, object]:
    cfg_path, cfg = _load_cfg_for_path(config_path)
    validation = validate_config_payload(cfg_path)
    health = health_payload(cfg_path)
    checks = health.get("checks", {})
    assert isinstance(checks, dict)
    blockers: list[str] = []

    if not bool(validation.get("ok")):
        blockers.append("config_validation_failed")
    if not bool(checks.get("rawpy")):
        blockers.append("missing_rawpy")
    if cfg.pipeline.use_ocio and not bool(checks.get("PyOpenColorIO")):
        blockers.append("missing_pyopencolorio")
    if cfg.output.write_prores_on_shot_complete and not bool(checks.get("ffmpeg")):
        blockers.append("missing_ffmpeg")

    return {
        "config_path": str(cfg_path),
        "ok": len(blockers) == 0,
        "blockers": blockers,
        "validation": validation,
        "health_checks": checks,
    }


def watch_start_payload(config_path: str | Path) -> dict[str, object]:
    cfg_path = Path(config_path).expanduser().resolve()
    cfg = load_config(cfg_path)
    preflight = watch_preflight_payload(cfg_path)
    state_file = _watch_state_file(cfg_path)
    existing = _read_watch_state(state_file)
    if existing is not None and _is_pid_running(int(existing.get("pid", 0))):
        payload = watch_state_payload(cfg_path)
        payload["preflight"] = preflight
        return payload

    if not bool(preflight.get("ok")):
        payload = watch_state_payload(cfg_path)
        payload["start_blocked"] = True
        payload["launch_error"] = f"watch start blocked by preflight: {', '.join(preflight.get('blockers', []))}"
        payload["preflight"] = preflight
        return payload

    log_path = cfg.watch.working_dir / "watch-service.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as log_f:
        cmd = [
            str(sys.executable),
            "-m",
            "stopmo_xcode.cli",
            "watch",
            "--config",
            str(cfg_path),
        ]
        proc = subprocess.Popen(
            cmd,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            cwd=str(Path.cwd()),
            start_new_session=True,
        )

    state = {
        "pid": int(proc.pid),
        "started_at_utc": _now_utc_iso(),
        "config_path": str(cfg_path),
        "log_path": str(log_path),
        "command": cmd,
    }
    _write_watch_state(state_file, state)
    time.sleep(0.25)
    payload = watch_state_payload(cfg_path)
    payload["start_blocked"] = False
    payload["preflight"] = preflight
    if not bool(payload.get("running")):
        payload["launch_error"] = "watch process exited early"
    return payload


def watch_stop_payload(config_path: str | Path, timeout_seconds: float = 5.0) -> dict[str, object]:
    cfg_path = Path(config_path).expanduser().resolve()
    state_file = _watch_state_file(cfg_path)
    state = _read_watch_state(state_file)
    if state is None:
        return watch_state_payload(cfg_path)

    pid = int(state.get("pid", 0)) if state.get("pid") is not None else None
    if _is_pid_running(pid):
        try:
            os.kill(int(pid), signal.SIGINT)
        except Exception:
            pass
        deadline = time.time() + max(0.5, float(timeout_seconds))
        while time.time() < deadline and _is_pid_running(pid):
            time.sleep(0.1)
        if _is_pid_running(pid):
            try:
                os.kill(int(pid), signal.SIGTERM)
            except Exception:
                pass
            deadline = time.time() + 2.0
            while time.time() < deadline and _is_pid_running(pid):
                time.sleep(0.1)
    if not _is_pid_running(pid) and state_file.exists():
        state_file.unlink()
    return watch_state_payload(cfg_path)


def watch_state_payload(config_path: str | Path, queue_limit: int = 200, log_tail_lines: int = 40) -> dict[str, object]:
    cfg_path = Path(config_path).expanduser().resolve()
    state_file = _watch_state_file(cfg_path)
    state = _read_watch_state(state_file) or {}

    pid = int(state.get("pid", 0)) if state.get("pid") is not None else None
    running = _is_pid_running(pid)
    if not running and state_file.exists():
        try:
            state_file.unlink()
        except Exception:
            pass

    queue = _queue_status_from_config(cfg_path, limit=queue_limit)
    counts = queue.get("counts", {})
    assert isinstance(counts, dict)
    total = int(sum(int(v) for v in counts.values()))
    completed = int(counts.get("done", 0)) + int(counts.get("failed", 0))
    inflight = (
        int(counts.get("detected", 0))
        + int(counts.get("decoding", 0))
        + int(counts.get("xform", 0))
        + int(counts.get("dpx_write", 0))
    )
    progress_ratio = (float(completed) / float(total)) if total > 0 else 0.0
    log_path = Path(str(state.get("log_path"))).expanduser().resolve() if state.get("log_path") else None
    runtime_state = _read_runtime_state(_runtime_state_file(cfg_path))

    return {
        "running": running,
        "pid": pid if running else None,
        "started_at_utc": state.get("started_at_utc"),
        "config_path": str(cfg_path),
        "log_path": str(log_path) if log_path else None,
        "log_tail": _tail_lines(log_path, max_lines=log_tail_lines),
        "queue": queue,
        "progress_ratio": progress_ratio,
        "completed_frames": completed,
        "inflight_frames": inflight,
        "total_frames": total,
        "crash_recovery": {
            "last_startup_utc": runtime_state.get("last_startup_utc"),
            "last_shutdown_utc": runtime_state.get("last_shutdown_utc"),
            "last_inflight_reset_count": int(runtime_state.get("last_inflight_reset_count", 0) or 0),
            "runtime_running": bool(runtime_state.get("running", False)),
        },
    }


def logs_diagnostics_payload(
    config_path: str | Path,
    *,
    severity: str | None = None,
    limit: int = 400,
) -> dict[str, object]:
    cfg_path, cfg = _load_cfg_for_path(config_path)
    watch_state = watch_state_payload(cfg_path, queue_limit=200, log_tail_lines=max(1, int(limit)))

    severity_filter: set[str] | None = None
    if severity:
        parts = [p.strip().upper() for p in str(severity).split(",") if p.strip()]
        severity_filter = set(parts) if parts else None

    candidate_logs: list[Path] = []
    watch_log = cfg.watch.working_dir / "watch-service.log"
    candidate_logs.append(watch_log)
    if cfg.log_file is not None:
        candidate_logs.append(cfg.log_file)

    merged_lines: list[str] = []
    sources: list[str] = []
    for log_path in candidate_logs:
        if log_path.exists():
            sources.append(str(log_path))
            merged_lines.extend(_read_log_lines(log_path, limit=limit))

    entries = _parse_log_lines(merged_lines[-max(1, int(limit)) :], severity_filter=severity_filter)
    warning_rows = _collect_diagnostic_warnings(entries)
    queue = watch_state["queue"]
    assert isinstance(queue, dict)
    queue_counts = queue.get("counts", {})
    assert isinstance(queue_counts, dict)

    return {
        "config_path": str(cfg_path),
        "log_sources": sources,
        "entries": entries,
        "warnings": warning_rows,
        "queue_counts": queue_counts,
        "watch_running": bool(watch_state.get("running")),
        "watch_pid": watch_state.get("pid"),
    }


def history_summary_payload(config_path: str | Path, *, limit: int = 30, gap_minutes: int = 30) -> dict[str, object]:
    cfg_path, cfg = _load_cfg_for_path(config_path)
    conn = sqlite3.connect(str(cfg.watch.db_path), timeout=30, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        jobs = conn.execute(
            """
            SELECT id, shot_name, state, output_path, detected_at, finished_at, updated_at
            FROM jobs
            ORDER BY detected_at ASC, id ASC
            """
        ).fetchall()
    finally:
        conn.close()

    runs: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    last_detected_ts: datetime | None = None
    gap_seconds = max(60, int(gap_minutes) * 60)

    def _flush() -> None:
        nonlocal current
        if current is None:
            return
        shots = sorted(set(current["shots"]))  # type: ignore[arg-type]
        outputs = sorted(set(current["outputs"]))  # type: ignore[arg-type]
        manifests = sorted(set(current["manifest_paths"]))  # type: ignore[arg-type]
        current["shots"] = shots
        current["outputs"] = outputs
        current["manifest_paths"] = manifests
        runs.append(current)
        current = None

    for row in jobs:
        detected_raw = row["detected_at"]
        if not detected_raw:
            continue
        detected_dt = datetime.fromisoformat(str(detected_raw))

        if current is None:
            current = {
                "run_id": f"run_{len(runs) + 1}",
                "start_utc": detected_dt.isoformat(),
                "end_utc": str(row["finished_at"] or row["updated_at"] or row["detected_at"]),
                "total_jobs": 0,
                "failed_jobs": 0,
                "counts": {},
                "shots": [],
                "outputs": [],
                "manifest_paths": [],
                "pipeline_hashes": [],
                "tool_versions": [],
            }
        elif last_detected_ts is not None:
            delta = (detected_dt - last_detected_ts).total_seconds()
            if delta > gap_seconds:
                _flush()
                current = {
                    "run_id": f"run_{len(runs) + 1}",
                    "start_utc": detected_dt.isoformat(),
                    "end_utc": str(row["finished_at"] or row["updated_at"] or row["detected_at"]),
                    "total_jobs": 0,
                    "failed_jobs": 0,
                    "counts": {},
                    "shots": [],
                    "outputs": [],
                    "manifest_paths": [],
                    "pipeline_hashes": [],
                    "tool_versions": [],
                }

        assert current is not None
        state = str(row["state"] or "unknown")
        counts = current["counts"]
        assert isinstance(counts, dict)
        counts[state] = int(counts.get(state, 0)) + 1
        current["total_jobs"] = int(current["total_jobs"]) + 1
        if state == "failed":
            current["failed_jobs"] = int(current["failed_jobs"]) + 1
        current["end_utc"] = str(row["finished_at"] or row["updated_at"] or row["detected_at"])

        shot_name = str(row["shot_name"] or "")
        if shot_name:
            current["shots"].append(shot_name)  # type: ignore[union-attr]
            manifest = cfg.watch.output_dir / shot_name / "manifest.json"
            if manifest.exists():
                current["manifest_paths"].append(str(manifest))  # type: ignore[union-attr]
                try:
                    payload = json.loads(manifest.read_text(encoding="utf-8"))
                    ph = payload.get("pipeline_hash")
                    tv = payload.get("tool_version")
                    if ph:
                        current["pipeline_hashes"].append(str(ph))  # type: ignore[union-attr]
                    if tv:
                        current["tool_versions"].append(str(tv))  # type: ignore[union-attr]
                except Exception:
                    pass
        out = row["output_path"]
        if out:
            current["outputs"].append(str(out))  # type: ignore[union-attr]
        last_detected_ts = detected_dt

    _flush()
    runs.reverse()
    return {
        "config_path": str(cfg_path),
        "db_path": str(cfg.watch.db_path),
        "count": len(runs[: max(1, int(limit))]),
        "runs": runs[: max(1, int(limit))],
    }


def copy_diagnostics_bundle_payload(
    config_path: str | Path,
    *,
    out_dir: str | Path | None = None,
    log_limit: int = 400,
) -> dict[str, object]:
    cfg_path, cfg = _load_cfg_for_path(config_path)
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base_dir = Path(out_dir).expanduser().resolve() if out_dir else (cfg.watch.working_dir / "diagnostics")
    base_dir.mkdir(parents=True, exist_ok=True)
    bundle_path = base_dir / f"diag_bundle_{now}.json"

    payload = {
        "created_at_utc": _now_utc_iso(),
        "config_path": str(cfg_path),
        "health": health_payload(cfg_path),
        "watch_state": watch_state_payload(cfg_path, queue_limit=250, log_tail_lines=80),
        "queue": queue_status_payload(cfg_path, limit=250),
        "shots": shots_summary_payload(cfg_path, limit=500),
        "logs_diagnostics": logs_diagnostics_payload(cfg_path, severity=None, limit=log_limit),
        "history": history_summary_payload(cfg_path, limit=30),
    }
    bundle_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return {
        "bundle_path": str(bundle_path),
        "created_at_utc": payload["created_at_utc"],
        "size_bytes": bundle_path.stat().st_size,
    }


def _wait_operation_with_events(operation_id: str, timeout_seconds: float | None = None) -> dict[str, object]:
    snapshot = app_api.wait_for_operation(operation_id, timeout_seconds=timeout_seconds)
    if snapshot is None:
        raise RuntimeError(f"operation not found: {operation_id}")
    events = app_api.poll_operation_events(operation_id=operation_id, limit=2000)
    return {
        "operation": asdict(snapshot),
        "events": [asdict(ev) for ev in events],
    }


def transcode_one_payload(
    config_path: str | Path,
    input_path: str | Path,
    output_dir: str | Path | None = None,
) -> dict[str, object]:
    op_id = app_api.start_transcode_one_operation(
        config_path=Path(config_path).expanduser().resolve(),
        input_path=Path(input_path).expanduser().resolve(),
        output_dir=Path(output_dir).expanduser().resolve() if output_dir else None,
    )
    payload = _wait_operation_with_events(op_id)
    payload["operation_id"] = op_id
    return payload


def suggest_matrix_payload(
    input_path: str | Path,
    camera_make_override: str | None = None,
    camera_model_override: str | None = None,
    write_json_path: str | Path | None = None,
) -> dict[str, object]:
    op_id = app_api.start_suggest_matrix_operation(
        input_path=Path(input_path).expanduser().resolve(),
        camera_make_override=camera_make_override,
        camera_model_override=camera_model_override,
        write_json_path=Path(write_json_path).expanduser().resolve() if write_json_path else None,
    )
    payload = _wait_operation_with_events(op_id)
    payload["operation_id"] = op_id
    return payload


def dpx_to_prores_payload(
    input_dir: str | Path,
    output_dir: str | Path | None = None,
    framerate: int = 24,
    overwrite: bool = True,
) -> dict[str, object]:
    op_id = app_api.start_dpx_to_prores_operation(
        input_dir=Path(input_dir).expanduser().resolve(),
        output_dir=Path(output_dir).expanduser().resolve() if output_dir else None,
        framerate=int(framerate),
        overwrite=bool(overwrite),
    )
    payload = _wait_operation_with_events(op_id)
    payload["operation_id"] = op_id
    return payload


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="stopmo-xcode-gui-bridge")
    sub = parser.add_subparsers(dest="command", required=True)

    cfg_read = sub.add_parser("config-read", help="Read config and emit JSON")
    cfg_read.add_argument("--config", required=True, help="Path to YAML config")

    cfg_write = sub.add_parser("config-write", help="Write config from JSON stdin")
    cfg_write.add_argument("--config", required=True, help="Path to YAML config")

    health = sub.add_parser("health", help="Emit runtime/dependency health as JSON")
    health.add_argument("--config", default=None, help="Optional config path to validate")

    queue_status = sub.add_parser("queue-status", help="Emit queue status JSON")
    queue_status.add_argument("--config", required=True, help="Path to YAML config")
    queue_status.add_argument("--limit", type=int, default=200, help="Recent jobs limit")

    shots_summary = sub.add_parser("shots-summary", help="Emit per-shot queue summary JSON")
    shots_summary.add_argument("--config", required=True, help="Path to YAML config")
    shots_summary.add_argument("--limit", type=int, default=500, help="Max shots")

    watch_start = sub.add_parser("watch-start", help="Launch watch service in background")
    watch_start.add_argument("--config", required=True, help="Path to YAML config")

    watch_stop = sub.add_parser("watch-stop", help="Stop background watch service")
    watch_stop.add_argument("--config", required=True, help="Path to YAML config")
    watch_stop.add_argument("--timeout", type=float, default=5.0, help="Stop timeout in seconds")

    watch_state = sub.add_parser("watch-state", help="Emit watch process + queue status JSON")
    watch_state.add_argument("--config", required=True, help="Path to YAML config")
    watch_state.add_argument("--limit", type=int, default=200, help="Recent jobs limit")
    watch_state.add_argument("--tail", type=int, default=40, help="Log tail line count")

    config_validate = sub.add_parser("config-validate", help="Validate config semantics and paths")
    config_validate.add_argument("--config", required=True, help="Path to YAML config")

    watch_preflight = sub.add_parser("watch-preflight", help="Run watch-service preflight checks")
    watch_preflight.add_argument("--config", required=True, help="Path to YAML config")

    logs_diag = sub.add_parser("logs-diagnostics", help="Emit structured logs + diagnostics summary")
    logs_diag.add_argument("--config", required=True, help="Path to YAML config")
    logs_diag.add_argument(
        "--severity",
        default=None,
        help="Optional comma-separated severity filter (e.g. ERROR,WARNING)",
    )
    logs_diag.add_argument("--limit", type=int, default=400, help="Max log entries")

    history = sub.add_parser("history-summary", help="Emit run history summary")
    history.add_argument("--config", required=True, help="Path to YAML config")
    history.add_argument("--limit", type=int, default=30, help="Max run rows")
    history.add_argument("--gap-minutes", type=int, default=30, help="Time gap used to separate runs")

    diag_bundle = sub.add_parser("copy-diagnostics-bundle", help="Write diagnostics bundle JSON")
    diag_bundle.add_argument("--config", required=True, help="Path to YAML config")
    diag_bundle.add_argument("--out-dir", default=None, help="Optional output directory for bundle")
    diag_bundle.add_argument("--log-limit", type=int, default=400, help="Max log entries in bundle")

    transcode_one = sub.add_parser("transcode-one", help="Run transcode-one operation and emit JSON")
    transcode_one.add_argument("--config", required=True, help="Path to YAML config")
    transcode_one.add_argument("--input", required=True, help="RAW input frame path")
    transcode_one.add_argument("--output-dir", default=None, help="Optional output directory override")

    suggest_matrix = sub.add_parser("suggest-matrix", help="Run suggest-matrix operation and emit JSON")
    suggest_matrix.add_argument("--input", required=True, help="RAW input frame path")
    suggest_matrix.add_argument("--camera-make", default=None, help="Optional camera make override")
    suggest_matrix.add_argument("--camera-model", default=None, help="Optional camera model override")
    suggest_matrix.add_argument("--write-json", default=None, help="Optional JSON report output path")

    dpx_to_prores = sub.add_parser("dpx-to-prores", help="Run DPX-to-ProRes batch operation and emit JSON")
    dpx_to_prores.add_argument("--input-dir", required=True, help="Input root directory containing dpx folders")
    dpx_to_prores.add_argument("--out-dir", default=None, help="Optional output directory")
    dpx_to_prores.add_argument("--framerate", type=int, default=24, help="Output framerate")
    dpx_to_prores.add_argument("--overwrite", action="store_true", default=True, help="Overwrite existing outputs")
    dpx_to_prores.add_argument(
        "--no-overwrite",
        dest="overwrite",
        action="store_false",
        help="Do not overwrite existing outputs",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "config-read":
            print(json.dumps(read_config_payload(args.config), indent=2))
            return 0
        if args.command == "config-write":
            payload = _read_json_stdin()
            print(json.dumps(write_config_payload(args.config, payload), indent=2))
            return 0
        if args.command == "health":
            print(json.dumps(health_payload(args.config), indent=2))
            return 0
        if args.command == "queue-status":
            print(json.dumps(queue_status_payload(args.config, limit=args.limit), indent=2))
            return 0
        if args.command == "shots-summary":
            print(json.dumps(shots_summary_payload(args.config, limit=args.limit), indent=2))
            return 0
        if args.command == "watch-start":
            print(json.dumps(watch_start_payload(args.config), indent=2))
            return 0
        if args.command == "watch-stop":
            print(json.dumps(watch_stop_payload(args.config, timeout_seconds=args.timeout), indent=2))
            return 0
        if args.command == "watch-state":
            print(json.dumps(watch_state_payload(args.config, queue_limit=args.limit, log_tail_lines=args.tail), indent=2))
            return 0
        if args.command == "config-validate":
            print(json.dumps(validate_config_payload(args.config), indent=2))
            return 0
        if args.command == "watch-preflight":
            print(json.dumps(watch_preflight_payload(args.config), indent=2))
            return 0
        if args.command == "logs-diagnostics":
            print(
                json.dumps(
                    logs_diagnostics_payload(
                        args.config,
                        severity=args.severity,
                        limit=args.limit,
                    ),
                    indent=2,
                )
            )
            return 0
        if args.command == "history-summary":
            print(
                json.dumps(
                    history_summary_payload(
                        args.config,
                        limit=args.limit,
                        gap_minutes=args.gap_minutes,
                    ),
                    indent=2,
                )
            )
            return 0
        if args.command == "copy-diagnostics-bundle":
            print(
                json.dumps(
                    copy_diagnostics_bundle_payload(
                        args.config,
                        out_dir=args.out_dir,
                        log_limit=args.log_limit,
                    ),
                    indent=2,
                )
            )
            return 0
        if args.command == "transcode-one":
            print(
                json.dumps(
                    transcode_one_payload(
                        config_path=args.config,
                        input_path=args.input,
                        output_dir=args.output_dir,
                    ),
                    indent=2,
                )
            )
            return 0
        if args.command == "suggest-matrix":
            print(
                json.dumps(
                    suggest_matrix_payload(
                        input_path=args.input,
                        camera_make_override=args.camera_make,
                        camera_model_override=args.camera_model,
                        write_json_path=args.write_json,
                    ),
                    indent=2,
                )
            )
            return 0
        if args.command == "dpx-to-prores":
            print(
                json.dumps(
                    dpx_to_prores_payload(
                        input_dir=args.input_dir,
                        output_dir=args.out_dir,
                        framerate=args.framerate,
                        overwrite=args.overwrite,
                    ),
                    indent=2,
                )
            )
            return 0
        parser.error(f"unknown command: {args.command}")
        return 2
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
