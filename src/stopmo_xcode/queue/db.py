"""SQLite-backed queue and shot-state persistence for deterministic frame processing."""

from __future__ import annotations

import dataclasses
import enum
import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class JobState(str, enum.Enum):
    """Canonical queue lifecycle states for frame jobs."""

    DETECTED = "detected"
    DECODING = "decoding"
    XFORM = "xform"
    DPX_WRITE = "dpx_write"
    DONE = "done"
    FAILED = "failed"


INFLIGHT_STATES = (JobState.DECODING.value, JobState.XFORM.value, JobState.DPX_WRITE.value)


@dataclass
class Job:
    """Queue job row representing one source frame through the processing lifecycle."""

    id: int
    source_path: str
    shot_name: str
    frame_number: int
    state: str
    attempts: int
    last_error: str | None
    worker_id: str | None
    detected_at: str
    updated_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Job":
        """Materialize a typed job from a SQLite row payload."""

        return cls(
            id=row["id"],
            source_path=row["source_path"],
            shot_name=row["shot_name"],
            frame_number=row["frame_number"],
            state=row["state"],
            attempts=row["attempts"],
            last_error=row["last_error"],
            worker_id=row["worker_id"],
            detected_at=row["detected_at"],
            updated_at=row["updated_at"],
        )


@dataclass
class ShotSettings:
    """Per-shot locked settings used to keep WB and exposure deterministic."""

    shot_name: str
    wb_multipliers: tuple[float, float, float, float]
    exposure_offset_stops: float
    reference_source_path: str
    created_at: str


class QueueDB:
    """Queue persistence API used by watcher, workers, service, and bridge surfaces."""

    def __init__(self, db_path: Path) -> None:
        """Open queue database connection and ensure required schema exists."""

        self.db_path = db_path
        self._conn = sqlite3.connect(str(db_path), timeout=30, isolation_level=None, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self.init_schema()

    def close(self) -> None:
        """Close the underlying SQLite connection."""

        self._conn.close()

    @staticmethod
    def _now() -> str:
        """Return current UTC timestamp for row update metadata."""

        return datetime.now(timezone.utc).isoformat()

    def init_schema(self) -> None:
        """Create queue, shot settings, and assembly tracking tables if missing."""

        self._conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_path TEXT NOT NULL UNIQUE,
                shot_name TEXT NOT NULL,
                frame_number INTEGER NOT NULL,
                state TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                worker_id TEXT,
                output_path TEXT,
                source_sha256 TEXT,
                detected_at TEXT NOT NULL,
                started_at TEXT,
                finished_at TEXT,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_jobs_state_detected
                ON jobs(state, detected_at);

            CREATE INDEX IF NOT EXISTS idx_jobs_shot_frame
                ON jobs(shot_name, frame_number);

            CREATE TABLE IF NOT EXISTS shot_settings (
                shot_name TEXT PRIMARY KEY,
                wb_multipliers_json TEXT NOT NULL,
                exposure_offset_stops REAL NOT NULL,
                reference_source_path TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS shot_assembly (
                shot_name TEXT PRIMARY KEY,
                last_frame_done_at TEXT NOT NULL,
                assembly_state TEXT NOT NULL,
                output_mov_path TEXT,
                review_mov_path TEXT,
                updated_at TEXT NOT NULL
            );
            """
        )

    def enqueue_detected(self, source_path: Path, shot_name: str, frame_number: int) -> bool:
        """Insert a newly detected frame job if it does not already exist."""

        now = self._now()
        try:
            self._conn.execute(
                """
                INSERT INTO jobs(source_path, shot_name, frame_number, state, detected_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (str(source_path), shot_name, frame_number, JobState.DETECTED.value, now, now),
            )
            return True
        except sqlite3.IntegrityError:
            return False

    def force_detected(self, source_path: Path, shot_name: str, frame_number: int) -> None:
        """Upsert a source job back to `detected` for one-shot transcode workflows."""

        now = self._now()
        self._conn.execute(
            """
            INSERT INTO jobs(source_path, shot_name, frame_number, state, detected_at, updated_at, started_at, finished_at, worker_id, last_error)
            VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)
            ON CONFLICT(source_path) DO UPDATE SET
              shot_name = excluded.shot_name,
              frame_number = excluded.frame_number,
              state = excluded.state,
              updated_at = excluded.updated_at,
              started_at = NULL,
              finished_at = NULL,
              worker_id = NULL,
              last_error = NULL
            """,
            (str(source_path), shot_name, frame_number, JobState.DETECTED.value, now, now),
        )

    def reset_inflight_to_detected(self) -> int:
        """Crash-recovery reset for inflight jobs back to `detected` on startup."""

        now = self._now()
        cur = self._conn.execute(
            f"""
            UPDATE jobs
            SET state = ?, updated_at = ?, worker_id = NULL, last_error = COALESCE(last_error, 'reset after restart')
            WHERE state IN ({','.join('?' for _ in INFLIGHT_STATES)})
            """,
            (JobState.DETECTED.value, now, *INFLIGHT_STATES),
        )
        return int(cur.rowcount)

    def lease_next_job(self, worker_id: str) -> Job | None:
        """Atomically lease the oldest detected job and transition it to `decoding`."""

        now = self._now()
        self._conn.execute("BEGIN IMMEDIATE")
        row = self._conn.execute(
            """
            SELECT * FROM jobs
            WHERE state = ?
            ORDER BY detected_at ASC, id ASC
            LIMIT 1
            """,
            (JobState.DETECTED.value,),
        ).fetchone()
        if row is None:
            self._conn.execute("COMMIT")
            return None

        job_id = row["id"]
        self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, attempts = attempts + 1, worker_id = ?, started_at = COALESCE(started_at, ?), updated_at = ?
            WHERE id = ? AND state = ?
            """,
            (
                JobState.DECODING.value,
                worker_id,
                now,
                now,
                job_id,
                JobState.DETECTED.value,
            ),
        )
        updated = self._conn.execute("SELECT changes() AS n").fetchone()["n"]
        self._conn.execute("COMMIT")
        if updated == 0:
            return None

        leased = self._conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return Job.from_row(leased)

    def lease_job_for_source(self, source_path: Path, worker_id: str) -> Job | None:
        """Atomically lease a specific source-path job for targeted debug processing."""

        now = self._now()
        self._conn.execute("BEGIN IMMEDIATE")
        row = self._conn.execute(
            """
            SELECT *
            FROM jobs
            WHERE source_path = ? AND state = ?
            LIMIT 1
            """,
            (str(source_path), JobState.DETECTED.value),
        ).fetchone()
        if row is None:
            self._conn.execute("COMMIT")
            return None

        job_id = row["id"]
        self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, attempts = attempts + 1, worker_id = ?, started_at = COALESCE(started_at, ?), updated_at = ?
            WHERE id = ? AND state = ?
            """,
            (
                JobState.DECODING.value,
                worker_id,
                now,
                now,
                job_id,
                JobState.DETECTED.value,
            ),
        )
        updated = self._conn.execute("SELECT changes() AS n").fetchone()["n"]
        self._conn.execute("COMMIT")
        if updated == 0:
            return None
        leased = self._conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return Job.from_row(leased)

    def transition(self, job_id: int, from_state: JobState, to_state: JobState, last_error: str | None = None) -> None:
        """Move a job between adjacent lifecycle states with optimistic-state guard."""

        now = self._now()
        self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, updated_at = ?, last_error = ?
            WHERE id = ? AND state = ?
            """,
            (to_state.value, now, last_error, job_id, from_state.value),
        )

    def mark_done(self, job_id: int, output_path: Path, source_sha256: str | None = None) -> None:
        """Finalize a job as done and persist output traceability metadata."""

        now = self._now()
        self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, updated_at = ?, finished_at = ?, output_path = ?, source_sha256 = ?, last_error = NULL
            WHERE id = ?
            """,
            (JobState.DONE.value, now, now, str(output_path), source_sha256, job_id),
        )

    def mark_failed(self, job_id: int, error: str) -> None:
        """Finalize a job as failed with last-error payload for diagnostics."""

        now = self._now()
        self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, updated_at = ?, finished_at = ?, last_error = ?
            WHERE id = ?
            """,
            (JobState.FAILED.value, now, now, error[:4000], job_id),
        )

    def stats(self) -> dict[str, int]:
        """Return counts per queue state for status and monitoring surfaces."""

        rows = self._conn.execute(
            "SELECT state, COUNT(*) AS n FROM jobs GROUP BY state ORDER BY state"
        ).fetchall()
        return {row["state"]: int(row["n"]) for row in rows}

    def shot_state_counts(self, shot_name: str) -> dict[str, int]:
        """Return per-state counts for a single shot with convenience totals."""

        rows = self._conn.execute(
            """
            SELECT state, COUNT(*) AS n
            FROM jobs
            WHERE shot_name = ?
            GROUP BY state
            """,
            (shot_name,),
        ).fetchall()
        counts: dict[str, int] = {row["state"]: int(row["n"]) for row in rows}
        counts["total"] = int(sum(counts.values()))
        counts["failed"] = int(counts.get(JobState.FAILED.value, 0))
        counts["inflight"] = int(sum(counts.get(state, 0) for state in INFLIGHT_STATES))
        return counts

    def retry_failed_for_shot(self, shot_name: str) -> int:
        """Reset failed jobs for one shot to detected for reprocessing."""

        now = self._now()
        cur = self._conn.execute(
            """
            UPDATE jobs
            SET state = ?, updated_at = ?, worker_id = NULL, started_at = NULL, finished_at = NULL,
                last_error = NULL, output_path = NULL, source_sha256 = NULL
            WHERE shot_name = ? AND state = ?
            """,
            (JobState.DETECTED.value, now, shot_name, JobState.FAILED.value),
        )
        return int(cur.rowcount)

    def restart_shot(self, shot_name: str, reset_locks: bool) -> dict[str, int | bool]:
        """Reset all jobs for a shot back to detected with optional lock reset."""

        counts = self.shot_state_counts(shot_name)
        if int(counts.get("inflight", 0)) > 0:
            raise ValueError("shot has inflight jobs and cannot be restarted")

        now = self._now()
        self._conn.execute("BEGIN IMMEDIATE")
        try:
            job_cur = self._conn.execute(
                """
                UPDATE jobs
                SET state = ?, attempts = 0, worker_id = NULL, started_at = NULL, finished_at = NULL,
                    last_error = NULL, output_path = NULL, source_sha256 = NULL, detected_at = ?, updated_at = ?
                WHERE shot_name = ?
                """,
                (JobState.DETECTED.value, now, now, shot_name),
            )

            settings_cleared = False
            if reset_locks:
                settings_cur = self._conn.execute("DELETE FROM shot_settings WHERE shot_name = ?", (shot_name,))
                settings_cleared = int(settings_cur.rowcount) > 0

            assembly_cur = self._conn.execute("DELETE FROM shot_assembly WHERE shot_name = ?", (shot_name,))
            assembly_cleared = int(assembly_cur.rowcount) > 0
            self._conn.execute("COMMIT")
        except Exception:
            self._conn.execute("ROLLBACK")
            raise

        return {
            "jobs_changed": int(job_cur.rowcount),
            "settings_cleared": bool(settings_cleared),
            "assembly_cleared": bool(assembly_cleared),
        }

    def delete_shot(self, shot_name: str) -> dict[str, int | bool]:
        """Delete one shot from queue/settings/assembly tables."""

        counts = self.shot_state_counts(shot_name)
        if int(counts.get("inflight", 0)) > 0:
            raise ValueError("shot has inflight jobs and cannot be deleted")

        self._conn.execute("BEGIN IMMEDIATE")
        try:
            jobs_cur = self._conn.execute("DELETE FROM jobs WHERE shot_name = ?", (shot_name,))
            settings_cur = self._conn.execute("DELETE FROM shot_settings WHERE shot_name = ?", (shot_name,))
            assembly_cur = self._conn.execute("DELETE FROM shot_assembly WHERE shot_name = ?", (shot_name,))
            self._conn.execute("COMMIT")
        except Exception:
            self._conn.execute("ROLLBACK")
            raise

        return {
            "jobs_deleted": int(jobs_cur.rowcount),
            "settings_cleared": int(settings_cur.rowcount) > 0,
            "assembly_cleared": int(assembly_cur.rowcount) > 0,
        }

    def recent_jobs(self, limit: int = 20) -> list[Job]:
        """Fetch most recently updated jobs for CLI/GUI inspection."""

        rows = self._conn.execute(
            """
            SELECT *
            FROM jobs
            ORDER BY updated_at DESC, id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [Job.from_row(r) for r in rows]

    def get_output_path(self, job_id: int) -> str | None:
        """Get output DPX path associated with a finished job."""

        row = self._conn.execute("SELECT output_path FROM jobs WHERE id = ?", (job_id,)).fetchone()
        if row is None:
            return None
        return row["output_path"]

    def get_shot_settings(self, shot_name: str) -> ShotSettings | None:
        """Read deterministic per-shot settings if already locked for that shot."""

        row = self._conn.execute(
            "SELECT * FROM shot_settings WHERE shot_name = ?",
            (shot_name,),
        ).fetchone()
        if row is None:
            return None
        wb = tuple(float(v) for v in json.loads(row["wb_multipliers_json"]))
        return ShotSettings(
            shot_name=row["shot_name"],
            wb_multipliers=(wb[0], wb[1], wb[2], wb[3]),
            exposure_offset_stops=float(row["exposure_offset_stops"]),
            reference_source_path=row["reference_source_path"],
            created_at=row["created_at"],
        )

    def set_shot_settings(
        self,
        shot_name: str,
        wb_multipliers: tuple[float, float, float, float],
        exposure_offset_stops: float,
        reference_source_path: Path,
    ) -> None:
        """Persist shot-level WB/exposure lock values derived from first frame."""

        now = self._now()
        self._conn.execute(
            """
            INSERT INTO shot_settings(shot_name, wb_multipliers_json, exposure_offset_stops, reference_source_path, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(shot_name) DO NOTHING
            """,
            (
                shot_name,
                json.dumps([float(v) for v in wb_multipliers]),
                float(exposure_offset_stops),
                str(reference_source_path),
                now,
                now,
            ),
        )

    def mark_shot_frame_done(self, shot_name: str) -> None:
        """Update last-done timestamp for shot assembly staleness tracking."""

        now = self._now()
        self._conn.execute(
            """
            INSERT INTO shot_assembly(shot_name, last_frame_done_at, assembly_state, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(shot_name) DO UPDATE SET
              last_frame_done_at = excluded.last_frame_done_at,
              updated_at = excluded.updated_at,
              assembly_state = CASE WHEN shot_assembly.assembly_state = 'done' THEN 'dirty' ELSE shot_assembly.assembly_state END
            """,
            (shot_name, now, "pending", now),
        )

    def shots_ready_for_assembly(self, stale_seconds: float) -> list[str]:
        """List shots with no recent completed frames and pending assembly work."""

        rows = self._conn.execute(
            """
            SELECT shot_name
            FROM shot_assembly
            WHERE assembly_state IN ('pending', 'dirty')
              AND (strftime('%s', 'now') - strftime('%s', last_frame_done_at)) >= ?
            ORDER BY last_frame_done_at ASC
            """,
            (int(stale_seconds),),
        ).fetchall()
        return [r["shot_name"] for r in rows]

    def mark_shot_assembly_done(
        self,
        shot_name: str,
        output_mov_path: Path,
        review_mov_path: Path | None,
    ) -> None:
        """Mark shot assembly completion and persist resulting media paths."""

        now = self._now()
        self._conn.execute(
            """
            UPDATE shot_assembly
            SET assembly_state = 'done', output_mov_path = ?, review_mov_path = ?, updated_at = ?
            WHERE shot_name = ?
            """,
            (str(output_mov_path), str(review_mov_path) if review_mov_path else None, now, shot_name),
        )

    def mark_shot_assembly_failed(self, shot_name: str) -> None:
        """Mark shot assembly failure so loops can retry and diagnostics can surface it."""

        now = self._now()
        self._conn.execute(
            """
            UPDATE shot_assembly
            SET assembly_state = 'pending', updated_at = ?
            WHERE shot_name = ?
            """,
            (now, shot_name),
        )


def asdict(job: Job) -> dict[str, Any]:
    """Convert a typed job row to a plain dictionary payload."""

    return dataclasses.asdict(job)
