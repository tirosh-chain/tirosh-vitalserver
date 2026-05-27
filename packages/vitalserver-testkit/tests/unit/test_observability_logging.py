from __future__ import annotations

import io
import json

from tirosh_vitalserver.testkit.observability import (
    configure_testkit_logging,
    emit_testkit_event,
)


def test_testkit_event_logging_defaults_to_json() -> None:
    stream = io.StringIO()
    configure_testkit_logging(format_name="json", stream=stream)

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


def test_testkit_event_logging_supports_logfmt() -> None:
    stream = io.StringIO()
    configure_testkit_logging(format_name="logfmt", stream=stream)

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
