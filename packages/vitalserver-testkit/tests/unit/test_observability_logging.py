from __future__ import annotations

import io
import json

from tirosh_vitalserver.testkit.configuration.logging_config import (
    configure_testkit_logging,
    load_logging_config,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event


def test_testkit_event_logging_defaults_to_json(tmp_path) -> None:
    config_path = write_logging_config(tmp_path, format_name="json")
    stream = io.StringIO()
    configure_testkit_logging(config_path=config_path, stream=stream)

    emit_testkit_event(
        "session.created",
        session_id="vrecorder-1",
        target_url="http://edge/",
        recorders=1,
    )

    payload = json.loads(stream.getvalue())

    assert payload["service"] == "testkit"
    assert payload["event"] == "session.created"
    assert payload["session_id"] == "vrecorder-1"
    assert payload["target_url"] == "http://edge/"
    assert payload["recorders"] == 1


def test_testkit_event_logging_supports_logfmt(tmp_path) -> None:
    config_path = write_logging_config(tmp_path, format_name="logfmt")
    stream = io.StringIO()
    configure_testkit_logging(config_path=config_path, stream=stream)

    emit_testkit_event(
        "stream.failed",
        vrcode="VR_TEST",
        error="connection refused",
    )

    line = stream.getvalue()

    assert "service=testkit" in line
    assert "event=stream.failed" in line
    assert "vrcode=VR_TEST" in line
    assert 'error="connection refused"' in line


def test_testkit_logging_reads_toml_config(tmp_path) -> None:
    config_path = write_logging_config(tmp_path, format_name="logfmt", level="DEBUG")
    stream = io.StringIO()

    configure_testkit_logging(config_path=config_path, stream=stream)
    emit_testkit_event("server.started")

    line = stream.getvalue()
    assert "level=info" in line
    assert "event=server.started" in line


def test_testkit_logging_toml_owns_event_logger(tmp_path) -> None:
    payload = load_logging_config(write_logging_config(tmp_path, format_name="json"))

    assert payload["version"] == 1
    assert payload["loggers"]["tirosh_vitalserver.testkit"]["handlers"] == ["stdout"]
    assert payload["loggers"]["tirosh_vitalserver.testkit"]["propagate"] is False


def write_logging_config(
    tmp_path,
    *,
    format_name: str,
    level: str = "INFO",
):
    config_path = tmp_path / "testkit.toml"
    config_path.write_text(
        f"""
[logging]
version = 1
disable_existing_loggers = false

[logging.formatters.testkit]
"()" = "tirosh_vitalserver.testkit.observability.TestKitEventFormatter"
format_name = "{format_name}"

[logging.handlers.stdout]
class = "logging.StreamHandler"
formatter = "testkit"
stream = "ext://sys.stdout"

[logging.loggers."tirosh_vitalserver.testkit"]
handlers = ["stdout"]
level = "{level}"
propagate = false
""".strip(),
        encoding="utf-8",
    )
    return config_path
