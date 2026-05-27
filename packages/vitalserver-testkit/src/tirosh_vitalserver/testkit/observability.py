"""Structured stdout logging for TestKit runtime events."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import Any

LOGGER_NAME = "tirosh_vitalserver.testkit"
SERVICE_NAME = "testkit"


def emit_testkit_event(
    event: str,
    *,
    level: int = logging.INFO,
    **fields: Any,
) -> None:
    """Emit one structured TestKit event."""

    logging.getLogger(LOGGER_NAME).log(
        level,
        event,
        extra={
            "testkit_event": {
                "event": event,
                **{key: value for key, value in fields.items() if value is not None},
            }
        },
    )


class TestKitEventFormatter(logging.Formatter):
    """Format TestKit event records as JSONL or logfmt."""

    def __init__(self, *, format_name: str) -> None:
        super().__init__()
        self.format_name = format_name

    def format(self, record: logging.LogRecord) -> str:
        event = getattr(record, "testkit_event", None)
        payload = {
            "ts": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname.lower(),
            "service": SERVICE_NAME,
        }
        if isinstance(event, dict):
            payload.update(event)
        else:
            payload["event"] = record.getMessage()

        if self.format_name == "logfmt":
            return logfmt(payload)
        return json.dumps(payload, separators=(",", ":"), ensure_ascii=False, default=str)


def logfmt(fields: dict[str, Any]) -> str:
    """Return a compact logfmt line."""

    return " ".join(
        f"{key}={logfmt_value(value)}"
        for key, value in fields.items()
        if value is not None
    )


def logfmt_value(value: Any) -> str:
    """Encode one logfmt value."""

    if isinstance(value, (dict, list, tuple)):
        text = json.dumps(value, separators=(",", ":"), ensure_ascii=False, default=str)
    else:
        text = str(value)
    if text == "":
        return '""'
    if any(character.isspace() or character in {'"', "="} for character in text):
        escaped = text.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return text
