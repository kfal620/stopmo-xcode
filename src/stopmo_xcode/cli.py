from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path
import sys

from stopmo_xcode.app_api import (
    convert_dpx_to_prores,
    get_status,
    run_transcode_one,
    run_watch,
    suggest_matrix,
)


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

    dpx_to_prores = sub.add_parser(
        "dpx-to-prores",
        help="Batch convert nested dpx sequences into LogC3 ProRes 4444 clips",
    )
    dpx_to_prores.add_argument("input_dir", help="Root directory containing shot subfolders with dpx folders")
    dpx_to_prores.add_argument(
        "--out-dir",
        default=None,
        help="Output root directory (default: <input_dir>/PRORES)",
    )
    dpx_to_prores.add_argument("--framerate", type=int, default=24, help="Output movie framerate")
    dpx_to_prores.add_argument(
        "--no-overwrite",
        action="store_true",
        help="Do not overwrite existing .mov files",
    )
    dpx_to_prores.add_argument("--json", action="store_true", help="Emit machine-readable JSON report")

    return parser


def _cmd_watch(args: argparse.Namespace) -> int:
    run_watch(args.config)
    return 0


def _cmd_transcode_one(args: argparse.Namespace) -> int:
    out_path = run_transcode_one(
        config_path=args.config,
        input_path=args.input,
        output_dir=args.out,
    )
    print(str(out_path))
    return 0


def _cmd_status(args: argparse.Namespace) -> int:
    status = get_status(config_path=args.config, limit=args.limit)
    payload = {
        "db_path": status.db_path,
        "counts": status.counts,
        "recent": [
            {
                "id": job.id,
                "state": job.state,
                "shot": job.shot,
                "frame": job.frame,
                "source": job.source,
                "attempts": job.attempts,
                "last_error": job.last_error,
                "updated_at": job.updated_at,
            }
            for job in status.recent
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


def _cmd_suggest_matrix(args: argparse.Namespace) -> int:
    result = suggest_matrix(
        input_path=args.input,
        camera_make_override=args.camera_make,
        camera_model_override=args.camera_model,
        write_json_path=args.write_json,
    )
    report = result.report
    payload = result.payload

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
    if result.json_report_path is not None:
        print(f"JSON report: {payload['json_report_path']}")
    return 0


def _cmd_dpx_to_prores(args: argparse.Namespace) -> int:
    result = convert_dpx_to_prores(
        input_dir=args.input_dir,
        output_dir=args.out_dir,
        framerate=int(args.framerate),
        overwrite=not bool(args.no_overwrite),
    )

    if args.json:
        payload = {
            "input_dir": str(result.input_dir),
            "output_dir": str(result.output_dir),
            "count": len(result.outputs),
            "outputs": [str(p) for p in result.outputs],
        }
        print(json.dumps(payload, indent=2))
        return 0

    print(f"Output root: {result.output_dir}")
    print(f"Created clips: {len(result.outputs)}")
    for p in result.outputs:
        print(f"  {p}")
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
        if args.command == "dpx-to-prores":
            return _cmd_dpx_to_prores(args)

        parser.error(f"unknown command: {args.command}")
        return 2
    except Exception as exc:
        logger.exception("fatal error")
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
