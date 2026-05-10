"""Recorder payload encoding helpers."""

from __future__ import annotations

import json
from collections.abc import Mapping

from tirosh_vitalserver.testkit.types.json import JsonValue


def recorder_payload_size_bytes(payload: Mapping[str, JsonValue]) -> int:
    """Return encoded JSON size for a recorder payload."""

    return len(
        json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    )
