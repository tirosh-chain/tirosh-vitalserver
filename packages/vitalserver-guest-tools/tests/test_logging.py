from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

from tirosh_guest_tools.domain.errors import GuestContractError
from tirosh_guest_tools.infrastructure.logging import JsonLogFormatter, dict_config
from tirosh_guest_tools.infrastructure.settings import (
    LoggingFormat,
    LoggingLevel,
    LoggingSettings,
)


def test_json_log_formatter_preserves_message_fields_and_error_code() -> None:
    formatter = JsonLogFormatter()
    logger = logging.getLogger("test.guest-tools")
    try:
        raise GuestContractError("missing field", code="runtime-config-field-missing")
    except GuestContractError:
        record = logger.makeRecord(
            logger.name,
            logging.ERROR,
            __file__,
            10,
            "contract failed",
            (),
            exc_info=sys.exc_info(),
            extra={"fields": {"requestId": "req-1"}},
        )

    document = json.loads(formatter.format(record))

    assert document["level"] == "error"
    assert document["message"] == "contract failed"
    assert document["fields"] == {"requestId": "req-1"}
    assert document["errorCode"] == "runtime-config-field-missing"
    assert document["exception"]["type"] == "GuestContractError"


def test_dict_config_declares_json_stream_and_file_handlers(
    tmp_path: Path,
) -> None:
    settings = LoggingSettings(
        format=LoggingFormat.JSON,
        level=LoggingLevel.WARNING,
        stream_enabled=True,
        file_enabled=True,
    )
    log_file = tmp_path / "guest.log"

    config = dict_config(settings, log_file=log_file)

    assert config["root"]["level"] == "WARNING"
    assert config["root"]["handlers"] == ["stderr", "file"]
    assert config["formatters"]["json"] == {"()": JsonLogFormatter}
    assert config["handlers"]["file"]["filename"] == str(log_file)
