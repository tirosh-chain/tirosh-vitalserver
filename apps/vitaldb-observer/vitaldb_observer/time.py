from __future__ import annotations

from datetime import UTC, datetime


def utc_now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def redis_unix_time_to_iso(raw_value: str | None) -> str | None:
    if raw_value is None or raw_value == "":
        return None
    try:
        timestamp = float(raw_value)
    except ValueError:
        return None
    if timestamp <= 0:
        return None
    return (
        datetime.fromtimestamp(timestamp, UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )
