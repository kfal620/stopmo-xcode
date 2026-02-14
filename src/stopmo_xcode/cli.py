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

        parser.error(f"unknown command: {args.command}")
        return 2
    except Exception as exc:
        logger.exception("fatal error")
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
