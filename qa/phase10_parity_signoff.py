#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

from stopmo_xcode.config import load_config
from stopmo_xcode.queue import QueueDB


@dataclass
class CheckResult:
    name: str
    status: str
    details: str


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _run(cmd: list[str], cwd: Path) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def _write_fixture_config(work_root: Path) -> Path:
    cfg = work_root / "config.yaml"
    cfg.write_text(
        """
watch:
  source_dir: ./incoming
  working_dir: ./work
  output_dir: ./out
  db_path: ./work/queue.sqlite3
""".strip()
        + "\n",
        encoding="utf-8",
    )
    return cfg


def _seed_queue(cfg_path: Path) -> dict[str, int]:
    cfg = load_config(cfg_path)
    db = QueueDB(cfg.watch.db_path)
    try:
        src_a = cfg.watch.source_dir / "SHOT_A_0001.CR3"
        src_b = cfg.watch.source_dir / "SHOT_A_0002.CR3"
        src_c = cfg.watch.source_dir / "SHOT_B_0001.CR3"
        src_a.write_bytes(b"a")
        src_b.write_bytes(b"b")
        src_c.write_bytes(b"c")

        assert db.enqueue_detected(src_a, shot_name="SHOT_A", frame_number=1)
        job_a = db.lease_next_job(worker_id="qa")
        assert job_a is not None
        db.mark_done(job_a.id, output_path=cfg.watch.output_dir / "SHOT_A" / "dpx" / "SHOT_A_0001.dpx")

        assert db.enqueue_detected(src_b, shot_name="SHOT_A", frame_number=2)
        job_b = db.lease_next_job(worker_id="qa")
        assert job_b is not None
        db.mark_failed(job_b.id, error="decode failed")

        assert db.enqueue_detected(src_c, shot_name="SHOT_B", frame_number=1)
        return db.stats()
    finally:
        db.close()


def _parse_json(stdout: str) -> dict[str, Any]:
    return json.loads(stdout) if stdout.strip() else {}


def run_signoff(repo_root: Path, report_dir: Path) -> tuple[list[CheckResult], Path]:
    python = repo_root / ".venv" / "bin" / "python"
    if not python.exists():
        raise RuntimeError(f"missing expected venv interpreter: {python}")

    report_dir.mkdir(parents=True, exist_ok=True)
    run_dir = report_dir / f"phase10_{_utc_now()}"
    run_dir.mkdir(parents=True, exist_ok=True)

    checks: list[CheckResult] = []

    with tempfile.TemporaryDirectory(prefix="phase10_", dir=str(run_dir)) as td:
        workspace = Path(td)
        cfg_path = _write_fixture_config(workspace)
        _seed_queue(cfg_path)

        # 1) CLI status parity with bridge queue-status
        rc_cli, out_cli, err_cli = _run(
            [str(python), "-m", "stopmo_xcode.cli", "status", "--config", str(cfg_path), "--json"],
            cwd=repo_root,
        )
        rc_bridge, out_bridge, err_bridge = _run(
            [str(python), "-m", "stopmo_xcode.gui_bridge", "queue-status", "--config", str(cfg_path)],
            cwd=repo_root,
        )
        if rc_cli == 0 and rc_bridge == 0:
            cli_payload = _parse_json(out_cli)
            bridge_payload = _parse_json(out_bridge)
            if cli_payload.get("counts") == bridge_payload.get("counts"):
                checks.append(CheckResult("status_vs_queue_status", "pass", "counts match"))
            else:
                checks.append(
                    CheckResult(
                        "status_vs_queue_status",
                        "fail",
                        f"counts mismatch cli={cli_payload.get('counts')} bridge={bridge_payload.get('counts')}",
                    )
                )
        else:
            checks.append(
                CheckResult(
                    "status_vs_queue_status",
                    "fail",
                    f"command failure cli_rc={rc_cli} bridge_rc={rc_bridge} cli_err={err_cli.strip()} bridge_err={err_bridge.strip()}",
                )
            )

        # 2) Bridge shots-summary smoke
        rc, out, err = _run(
            [str(python), "-m", "stopmo_xcode.gui_bridge", "shots-summary", "--config", str(cfg_path)],
            cwd=repo_root,
        )
        if rc == 0:
            payload = _parse_json(out)
            shots = payload.get("shots", [])
            ok = isinstance(shots, list) and len(shots) >= 2
            checks.append(CheckResult("shots_summary_smoke", "pass" if ok else "fail", f"shot_rows={len(shots) if isinstance(shots, list) else 'n/a'}"))
        else:
            checks.append(CheckResult("shots_summary_smoke", "fail", err.strip()))

        # 3) DPX-to-ProRes parity on empty input (no ffmpeg required)
        empty_root = workspace / "empty_output_root"
        empty_root.mkdir(parents=True, exist_ok=True)
        rc_cli, out_cli, err_cli = _run(
            [str(python), "-m", "stopmo_xcode.cli", "dpx-to-prores", str(empty_root), "--json"],
            cwd=repo_root,
        )
        rc_bridge, out_bridge, err_bridge = _run(
            [str(python), "-m", "stopmo_xcode.gui_bridge", "dpx-to-prores", "--input-dir", str(empty_root)],
            cwd=repo_root,
        )
        if rc_cli == 0 and rc_bridge == 0:
            cli_payload = _parse_json(out_cli)
            bridge_payload = _parse_json(out_bridge)
            op = bridge_payload.get("operation", {})
            result = op.get("result", {}) if isinstance(op, dict) else {}
            cli_count = int(cli_payload.get("count", -1))
            bridge_count = int(result.get("count", -1)) if isinstance(result, dict) else -1
            if cli_count == bridge_count == 0:
                checks.append(CheckResult("dpx_to_prores_empty_parity", "pass", "both report zero outputs"))
            else:
                checks.append(
                    CheckResult(
                        "dpx_to_prores_empty_parity",
                        "fail",
                        f"count mismatch cli={cli_count} bridge={bridge_count}",
                    )
                )
        else:
            checks.append(
                CheckResult(
                    "dpx_to_prores_empty_parity",
                    "fail",
                    f"command failure cli_rc={rc_cli} bridge_rc={rc_bridge} cli_err={err_cli.strip()} bridge_err={err_bridge.strip()}",
                )
            )

        # 4) transcode-one failure path parity (invalid input)
        missing_raw = workspace / "missing.CR3"
        rc_cli, _, _ = _run(
            [str(python), "-m", "stopmo_xcode.cli", "transcode-one", str(missing_raw), "--config", str(cfg_path)],
            cwd=repo_root,
        )
        rc_bridge, out_bridge, err_bridge = _run(
            [
                str(python),
                "-m",
                "stopmo_xcode.gui_bridge",
                "transcode-one",
                "--config",
                str(cfg_path),
                "--input",
                str(missing_raw),
            ],
            cwd=repo_root,
        )
        if rc_bridge == 0:
            bridge_payload = _parse_json(out_bridge)
            status = bridge_payload.get("operation", {}).get("status")
            ok = rc_cli != 0 and status == "failed"
            checks.append(CheckResult("transcode_one_failure_parity", "pass" if ok else "fail", f"cli_rc={rc_cli} bridge_status={status}"))
        else:
            checks.append(CheckResult("transcode_one_failure_parity", "fail", err_bridge.strip()))

        # 5) suggest-matrix failure path parity (invalid input)
        rc_cli, _, _ = _run(
            [str(python), "-m", "stopmo_xcode.cli", "suggest-matrix", str(missing_raw), "--json"],
            cwd=repo_root,
        )
        rc_bridge, out_bridge, err_bridge = _run(
            [str(python), "-m", "stopmo_xcode.gui_bridge", "suggest-matrix", "--input", str(missing_raw)],
            cwd=repo_root,
        )
        if rc_bridge == 0:
            bridge_payload = _parse_json(out_bridge)
            status = bridge_payload.get("operation", {}).get("status")
            ok = rc_cli != 0 and status == "failed"
            checks.append(CheckResult("suggest_matrix_failure_parity", "pass" if ok else "fail", f"cli_rc={rc_cli} bridge_status={status}"))
        else:
            checks.append(CheckResult("suggest_matrix_failure_parity", "fail", err_bridge.strip()))

        # 6) Diagnostics + history + bundle smoke
        smoke_fail = []
        for args in (
            ["logs-diagnostics", "--config", str(cfg_path)],
            ["history-summary", "--config", str(cfg_path)],
            ["copy-diagnostics-bundle", "--config", str(cfg_path), "--out-dir", str(workspace / "diag")],
        ):
            rc, _, err = _run([str(python), "-m", "stopmo_xcode.gui_bridge", *args], cwd=repo_root)
            if rc != 0:
                smoke_fail.append(f"{args[0]}: {err.strip()}")
        checks.append(
            CheckResult(
                "diagnostics_history_smoke",
                "pass" if not smoke_fail else "fail",
                "ok" if not smoke_fail else "; ".join(smoke_fail),
            )
        )

        # 7) Validation + preflight smoke
        smoke_fail = []
        for args in (
            ["config-validate", "--config", str(cfg_path)],
            ["watch-preflight", "--config", str(cfg_path)],
        ):
            rc, _, err = _run([str(python), "-m", "stopmo_xcode.gui_bridge", *args], cwd=repo_root)
            if rc != 0:
                smoke_fail.append(f"{args[0]}: {err.strip()}")
        checks.append(
            CheckResult(
                "validation_preflight_smoke",
                "pass" if not smoke_fail else "fail",
                "ok" if not smoke_fail else "; ".join(smoke_fail),
            )
        )

    return checks, run_dir


def write_reports(checks: list[CheckResult], out_dir: Path) -> tuple[Path, Path]:
    summary = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "total": len(checks),
        "passed": len([c for c in checks if c.status == "pass"]),
        "failed": len([c for c in checks if c.status == "fail"]),
        "checks": [asdict(c) for c in checks],
    }
    json_path = out_dir / "parity_signoff.json"
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Phase 10 Parity Signoff",
        "",
        f"- Created: {summary['created_at_utc']}",
        f"- Total checks: {summary['total']}",
        f"- Passed: {summary['passed']}",
        f"- Failed: {summary['failed']}",
        "",
        "| Check | Status | Details |",
        "|---|---|---|",
    ]
    for c in checks:
        lines.append(f"| {c.name} | {c.status.upper()} | {c.details.replace('|', '/')} |")
    md_path = out_dir / "parity_signoff.md"
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run CLI-vs-GUI parity QA signoff checks.")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd(), help="Repository root")
    parser.add_argument("--report-dir", type=Path, default=Path("qa/reports"), help="Output reports directory")
    args = parser.parse_args()

    repo_root = args.repo_root.expanduser().resolve()
    report_dir = args.report_dir.expanduser().resolve()

    checks, out_dir = run_signoff(repo_root=repo_root, report_dir=report_dir)
    json_path, md_path = write_reports(checks, out_dir)

    failed = [c for c in checks if c.status == "fail"]
    print(f"phase10 signoff report: {md_path}")
    print(f"phase10 signoff json:   {json_path}")
    print(f"checks: total={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
