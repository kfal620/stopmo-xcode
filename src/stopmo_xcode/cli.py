from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path
import sys

from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB
from stopmo_xcode.utils.logging_utils import configure_logging


logger = logging.getLogger(__name__)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="stopmo-xcode")
    sub = parser.add_subparsers(dest="command", required=True)

    watch = sub.add_parser("watch", help="Watch source folder and process incoming RAW frames")
    watch.add_argument("--config", required=True, help="Path to YAML config")

    one = sub.add_parser("transcode-one", help="Transcode one RAW frame for debug")
    one.add_argument("input", help="Input RAW frame path")
    one.add_argument("--config", required=True, help="Path to YAML config")
    one.add_argument("--out", default=None, help="Optional output root override")

    status = sub.add_parser("status", help="Show queue DB status")
    status.add_argument("--config", required=True, help="Path to YAML config")
    status.add_argument("--limit", type=int, default=20, help="Recent jobs limit")
    status.add_argument("--json", action="store_true", help="Emit machine-readable JSON")

    suggest = sub.add_parser(
        "suggest-matrix",
        help="Suggest pipeline.camera_to_reference_matrix from RAW metadata",
    )
    suggest.add_argument("input", help="Input RAW frame path")
    suggest.add_argument("--camera-make", default=None, help="Optional make override for known matrix fallback")
    suggest.add_argument("--camera-model", default=None, help="Optional model override for known matrix fallback")
    suggest.add_argument("--json", action="store_true", help="Emit machine-readable JSON report")
    suggest.add_argument("--write-json", default=None, help="Optional path to write JSON report")

    return parser


def _cmd_watch(args: argparse.Namespace) -> int:
    from stopmo_xcode.service import run_watch_service

    config = load_config(args.config)
    configure_logging(config.log_level, config.log_file)
    run_watch_service(config)
    return 0


def _cmd_transcode_one(args: argparse.Namespace) -> int:
    from stopmo_xcode.service import transcode_one

    config = load_config(args.config)
    configure_logging(config.log_level, config.log_file)

    input_path = Path(args.input).expanduser().resolve()
    output_override = Path(args.out).expanduser().resolve() if args.out else None

    out_path = transcode_one(config, input_path=input_path, output_dir=output_override)
    print(str(out_path))
    return 0


def _cmd_status(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    configure_logging(config.log_level, config.log_file)

    db = QueueDB(config.watch.db_path)
    try:
        stats = db.stats()
        jobs = db.recent_jobs(limit=args.limit)

        payload = {
            "db_path": str(config.watch.db_path),
            "counts": stats,
            "recent": [
                {
                    "id": j.id,
                    "state": j.state,
                    "shot": j.shot_name,
                    "frame": j.frame_number,
                    "source": j.source_path,
                    "attempts": j.attempts,
                    "last_error": j.last_error,
                    "updated_at": j.updated_at,
                }
                for j in jobs
            ],
        }

        if args.json:
            print(json.dumps(payload, indent=2))
            return 0

        print(f"Queue DB: {payload['db_path']}")
        print("State counts:")
        for state in sorted(payload["counts"]):
            print(f"  {state:>10}: {payload['counts'][state]}")

        print("Recent jobs:")
        for j in payload["recent"]:
            print(
                f"  #{j['id']:04d} {j['state']:<10} shot={j['shot']} frame={j['frame']} "
                f"attempts={j['attempts']} source={Path(j['source']).name}"
            )
            if j["last_error"]:
                print(f"      error={j['last_error']}")

        return 0
    finally:
        db.close()


def _cmd_suggest_matrix(args: argparse.Namespace) -> int:
    from stopmo_xcode.color.matrix_suggest import suggest_camera_to_reference_matrix

    input_path = Path(args.input).expanduser().resolve()
    report = suggest_camera_to_reference_matrix(
        input_path,
        reference_space="ACES2065-1",
        camera_make_override=args.camera_make,
        camera_model_override=args.camera_model,
    )
    payload = report.to_json_dict()

    if args.write_json:
        out = Path(args.write_json).expanduser().resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        payload["json_report_path"] = str(out)

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    camera_text = " ".join(v for v in [report.camera_make, report.camera_model] if v) or "unknown"
    print(f"Input RAW: {report.input_path}")
    print(f"Camera: {camera_text}")
    print(f"Source: {report.source} (confidence: {report.confidence})")
    print("Assumptions:")
    for line in report.assumptions:
        print(f"  - {line}")
    if report.notes:
        print("Notes:")
        for line in report.notes:
            print(f"  - {line}")
    if report.warnings:
        print("Warnings:")
        for line in report.warnings:
            print(f"  - {line}")
    print("Suggested YAML snippet:")
    print(report.to_yaml_block())
    if args.write_json:
        print(f"JSON report: {payload['json_report_path']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "watch":
            return _cmd_watch(args)
        if args.command == "transcode-one":
            return _cmd_transcode_one(args)
        if args.command == "status":
            return _cmd_status(args)
        if args.command == "suggest-matrix":
            return _cmd_suggest_matrix(args)

        parser.error(f"unknown command: {args.command}")
        return 2
    except Exception as exc:
        logger.exception("fatal error")
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
