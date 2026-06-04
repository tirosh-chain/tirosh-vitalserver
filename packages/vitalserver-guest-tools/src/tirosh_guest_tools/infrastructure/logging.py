from __future__ import annotations

import json
import logging
import logging.config
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.errors import GuestToolsDomainError
from tirosh_guest_tools.infrastructure.settings import LoggingFormat, LoggingSettings

LOG_RECORD_RESERVED = {
    "args",
    "asctime",
    "created",
    "exc_info",
    "exc_text",
    "filename",
    "funcName",
    "levelname",
    "levelno",
    "lineno",
    "message",
    "module",
    "msecs",
    "msg",
    "name",
    "pathname",
    "process",
    "processName",
    "relativeCreated",
    "stack_info",
    "thread",
    "threadName",
}


class JsonLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        document: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC)
            .isoformat()
            .replace("+00:00", "Z"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
        }
        fields = getattr(record, "fields", None)
        if isinstance(fields, dict):
            document["fields"] = json_safe(fields)
        extra = extra_fields(record)
        if extra:
            document["extra"] = json_safe(extra)
        if record.exc_info:
            exception = record.exc_info[1]
            document["exception"] = {
                "type": type(exception).__name__ if exception else "",
                "message": str(exception) if exception else "",
                "traceback": self.formatException(record.exc_info),
            }
            if isinstance(exception, GuestToolsDomainError):
                document["errorCode"] = exception.code
        return json.dumps(document, sort_keys=True, separators=(",", ":"))


def configure_logging(
    settings: LoggingSettings,
    *,
    log_file: Path | None = None,
) -> logging.Logger:
    if settings.format is not LoggingFormat.JSON:
        raise ValueError(f"unsupported logging format: {settings.format}")

    logging.config.dictConfig(dict_config(settings, log_file=log_file))
    return logging.getLogger()


def dict_config(
    settings: LoggingSettings,
    *,
    log_file: Path | None = None,
) -> dict[str, Any]:
    handlers: dict[str, dict[str, Any]] = {}
    root_handlers: list[str] = []
    if settings.stream_enabled:
        handlers["stderr"] = {
            "class": "logging.StreamHandler",
            "formatter": "json",
            "stream": "ext://sys.stderr",
        }
        root_handlers.append("stderr")
    if settings.file_enabled and log_file is not None:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers["file"] = {
            "class": "logging.FileHandler",
            "encoding": "utf-8",
            "filename": str(log_file),
            "formatter": "json",
        }
        root_handlers.append("file")

    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "json": {"()": JsonLogFormatter},
        },
        "handlers": handlers,
        "root": {
            "handlers": root_handlers,
            "level": settings.level.value.upper(),
        },
    }


def extra_fields(record: logging.LogRecord) -> dict[str, object]:
    return {
        key: value
        for key, value in record.__dict__.items()
        if key not in LOG_RECORD_RESERVED and key != "fields"
    }


def json_safe(value: object) -> object:
    try:
        json.dumps(value)
    except TypeError:
        if isinstance(value, dict):
            return {str(key): json_safe(item) for key, item in value.items()}
        if isinstance(value, list | tuple | set):
            return [json_safe(item) for item in value]
        return str(value)
    return value
