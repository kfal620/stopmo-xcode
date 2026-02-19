from __future__ import annotations

import json
import logging
import multiprocessing as mp
from pathlib import Path
import shutil
import threading
import time
from datetime import datetime, timezone

from stopmo_xcode.assemble import (
    AssemblyError,
    assemble_logc_prores_4444,
    assemble_rec709_review,
    write_handoff_readme,
)
from stopmo_xcode.config import AppConfig
from stopmo_xcode.queue import QueueDB
from stopmo_xcode.utils.shot import infer_frame_number, infer_shot_name
from stopmo_xcode.watcher.source_watcher import SourceWatcher
from stopmo_xcode.worker import JobProcessor


logger = logging.getLogger(__name__)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _runtime_state_path(config: AppConfig) -> Path:
    return config.watch.working_dir / ".stopmo_runtime_state.json"


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


def _write_runtime_state(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _worker_main(config: AppConfig, worker_id: str, stop_event: mp.Event) -> None:
    db = QueueDB(config.watch.db_path)
    processor = JobProcessor(config=config, db=db)
    logger.info("worker %s started", worker_id)

    try:
        while not stop_event.is_set():
            job = db.lease_next_job(worker_id=worker_id)
            if job is None:
                time.sleep(0.25)
                continue
            processor.process_job(job)
    except KeyboardInterrupt:
        logger.info("worker %s interrupted; exiting", worker_id)
    finally:
        db.close()


def _assembly_loop(config: AppConfig, stop_event: threading.Event) -> None:
    if not config.output.write_prores_on_shot_complete:
        return

    db = QueueDB(config.watch.db_path)
    logger.info("shot assembly loop enabled")

    try:
        while not stop_event.is_set():
            ready = db.shots_ready_for_assembly(stale_seconds=config.watch.shot_complete_seconds)
            for shot_name in ready:
                try:
                    shot_dir = config.watch.output_dir / shot_name
                    dpx_pattern = str(shot_dir / "dpx" / "*.dpx")
                    out_mov = shot_dir / f"{shot_name}_logc3_awg_prores4444.mov"
                    assemble_logc_prores_4444(
                        dpx_glob=dpx_pattern,
                        out_mov=out_mov,
                        framerate=config.output.framerate,
                    )

                    review_mov = None
                    if config.output.show_lut_rec709_path is not None and config.output.show_lut_rec709_path.exists():
                        review_mov = shot_dir / f"{shot_name}_review_rec709.mov"
                        assemble_rec709_review(
                            in_mov=out_mov,
                            out_mov=review_mov,
                            show_lut_cube=config.output.show_lut_rec709_path,
                        )
                        shutil.copy2(config.output.show_lut_rec709_path, shot_dir / "show_lut_rec709.cube")

                    write_handoff_readme(shot_dir / "README.txt")
                    db.mark_shot_assembly_done(shot_name, output_mov_path=out_mov, review_mov_path=review_mov)
                    logger.info("assembled shot %s -> %s", shot_name, out_mov)
                except AssemblyError:
                    db.mark_shot_assembly_failed(shot_name)
                    logger.exception("shot assembly failed for %s", shot_name)
                except Exception:
                    db.mark_shot_assembly_failed(shot_name)
                    logger.exception("unexpected assembly failure for %s", shot_name)
            time.sleep(2.0)
    finally:
        db.close()


def run_watch_service(config: AppConfig, shutdown_event: threading.Event | None = None) -> None:
    db = QueueDB(config.watch.db_path)
    reset_count = db.reset_inflight_to_detected()
    if reset_count:
        logger.warning("reset %s inflight jobs to detected after startup", reset_count)
    runtime_state_path = _runtime_state_path(config)
    runtime_state = _read_runtime_state(runtime_state_path)
    runtime_state["last_startup_utc"] = _utc_now_iso()
    runtime_state["last_inflight_reset_count"] = int(reset_count)
    runtime_state["last_db_path"] = str(config.watch.db_path)
    runtime_state["running"] = True
    _write_runtime_state(runtime_state_path, runtime_state)

    def on_ready(path: Path) -> None:
        shot_name = infer_shot_name(path, shot_regex=config.watch.shot_regex)
        frame = infer_frame_number(path)
        inserted = db.enqueue_detected(path, shot_name=shot_name, frame_number=frame)
        if inserted:
            logger.info("queued %s shot=%s frame=%s", path.name, shot_name, frame)

    watcher = SourceWatcher(
        source_dir=config.watch.source_dir,
        include_extensions=config.watch.include_extensions,
        stable_seconds=config.watch.stable_seconds,
        poll_interval_seconds=config.watch.poll_interval_seconds,
        scan_interval_seconds=config.watch.scan_interval_seconds,
        on_ready_file=on_ready,
    )

    ctx = mp.get_context("spawn")
    stop_event = ctx.Event()
    workers: list[mp.Process] = []

    for idx in range(max(1, config.watch.max_workers)):
        worker_id = f"worker-{idx + 1}"
        proc = ctx.Process(target=_worker_main, args=(config, worker_id, stop_event), daemon=True)
        proc.start()
        workers.append(proc)

    assembly_stop = threading.Event()
    assembly_thread = threading.Thread(target=_assembly_loop, args=(config, assembly_stop), daemon=True)
    assembly_thread.start()

    logger.info("watcher started with %s workers", len(workers))

    try:
        watcher.run_forever(external_stop_event=shutdown_event)
    except KeyboardInterrupt:
        logger.info("interrupt received, shutting down")
    finally:
        watcher.stop()
        stop_event.set()
        assembly_stop.set()
        for proc in workers:
            proc.join(timeout=5)
            if proc.is_alive():
                proc.terminate()
        assembly_thread.join(timeout=2)
        runtime_state = _read_runtime_state(runtime_state_path)
        runtime_state["running"] = False
        runtime_state["last_shutdown_utc"] = _utc_now_iso()
        _write_runtime_state(runtime_state_path, runtime_state)
        db.close()


def transcode_one(config: AppConfig, input_path: Path, output_dir: Path | None = None) -> Path:
    db = QueueDB(config.watch.db_path)
    processor = JobProcessor(config=config, db=db)

    shot_name = infer_shot_name(input_path, shot_regex=config.watch.shot_regex)
    frame_number = infer_frame_number(input_path)

    if output_dir is not None:
        original_output = config.watch.output_dir
        config.watch.output_dir = output_dir
    else:
        original_output = None

    try:
        db.force_detected(input_path, shot_name=shot_name, frame_number=frame_number)
        job = db.lease_job_for_source(source_path=input_path, worker_id="transcode-one")
        if job is None:
            raise RuntimeError("unable to lease transcode-one job")

        processor.process_job(job)
        done_rows = [j for j in db.recent_jobs(limit=200) if j.source_path == str(input_path)]
        if not done_rows:
            raise RuntimeError("transcode-one finished with no resulting job row")
        top = done_rows[0]
        if top.state != "done":
            raise RuntimeError(f"transcode-one failed with state={top.state} error={top.last_error}")
        out_value = db.get_output_path(top.id)
        if not out_value:
            raise RuntimeError("transcode-one completed but output path is missing")
        output_path = Path(out_value)
        return output_path
    finally:
        if original_output is not None:
            config.watch.output_dir = original_output
        db.close()
