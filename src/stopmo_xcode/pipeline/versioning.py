"""Stable hashing helper for pipeline config identity fingerprints."""

from __future__ import annotations

import hashlib
import json
from typing import Any


def stable_pipeline_hash(payload: dict[str, Any]) -> str:
    """Return short deterministic hash for JSON-serializable pipeline payload."""

    blob = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:16]
