from __future__ import annotations

from collections.abc import Iterator

import pytest

from tirosh_vitalserver.testkit.application.usecases.server.hl7 import (
    Hl7Poller,
    Hl7PollState,
)
from tirosh_vitalserver.testkit.errors import Hl7ParseError, Hl7RequestError
from tirosh_vitalserver.testkit.schemas.hl7 import Hl7Message, Hl7Observation
from tirosh_vitalserver.testkit.schemas.http import HttpResponse

HL7_BODY = (
    b"\x0b"
    b"MSH|^~&|||||||ORU^R01|VR|P|2.3||||||8859/1\n"
    b"PID|||PATIENT001^^^^MR||???^\"\"||\"\"|U\n"
    b"PV1||I|OR^^OR&ICU&BED01\n"
    b"OBR|||||||20260901143025\n"
    b"OBX||NM|SpHb|0|12.3|g/dL|||||F\n"
    b"\x1c\n"
)


class FakeHl7Source:
    def __init__(self, responses: list[HttpResponse]) -> None:
        self._responses: Iterator[HttpResponse] = iter(responses)

    def fetch_hl7(self) -> HttpResponse:
        return next(self._responses)


def _sample_messages() -> tuple[Hl7Message, ...]:
    return (
        Hl7Message(
            version="2.3",
            patient_id="PATIENT001",
            group="ICU",
            bed_name="BED01",
            observed_at="20260901143025",
            observations=(
                Hl7Observation(
                    value_type="NM",
                    identifier="SpHb",
                    sub_id="0",
                    value="12.3",
                    unit="g/dL",
                    status="F",
                ),
            ),
        ),
    )


class FakeHl7Decoder:
    def decode(self, payload: bytes) -> tuple[Hl7Message, ...]:
        if payload == b"":
            return ()
        return _sample_messages()


class ScriptedHl7Decoder:
    """Decoder test double with one explicit outcome per call."""

    def __init__(
        self,
        outcomes: list[Exception | tuple[Hl7Message, ...]],
    ) -> None:
        self._outcomes: Iterator[Exception | tuple[Hl7Message, ...]] = iter(outcomes)

    def decode(self, payload: bytes) -> tuple[Hl7Message, ...]:
        outcome = next(self._outcomes)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def _response(body: bytes, status_code: int = 200) -> HttpResponse:
    return HttpResponse(
        status_code=status_code,
        headers={"content-type": "text/html; charset=utf-8"},
        body=body,
        elapsed_seconds=0.01,
    )


def test_poll_once_distinguishes_data_unchanged_and_empty() -> None:
    source = FakeHl7Source(
        [_response(HL7_BODY), _response(HL7_BODY), _response(b"")]
    )
    poller = Hl7Poller(source, FakeHl7Decoder())

    first = poller.poll_once()
    second = poller.poll_once()
    third = poller.poll_once()

    assert first.state is Hl7PollState.DATA
    assert len(first.messages) == 1
    assert second.state is Hl7PollState.UNCHANGED
    assert len(second.messages) == 1
    assert third.state is Hl7PollState.EMPTY
    assert third.messages == ()


def test_poll_once_propagates_parse_error_without_recording_digest() -> None:
    parse_error = Hl7ParseError("invalid HL7 payload")
    messages = _sample_messages()
    poller = Hl7Poller(
        FakeHl7Source([_response(HL7_BODY), _response(HL7_BODY)]),
        ScriptedHl7Decoder([parse_error, messages]),
    )

    with pytest.raises(Hl7ParseError) as exc_info:
        poller.poll_once()

    assert exc_info.value is parse_error

    result = poller.poll_once()

    assert result.state is Hl7PollState.DATA
    assert result.messages == messages


def test_poll_once_reports_non_success_http_response() -> None:
    poller = Hl7Poller(
        FakeHl7Source([_response(b"failure", status_code=503)]),
        FakeHl7Decoder(),
    )

    with pytest.raises(Hl7RequestError, match="HTTP 503"):
        poller.poll_once()


def test_poll_rejects_non_positive_interval() -> None:
    poller = Hl7Poller(
        FakeHl7Source([_response(HL7_BODY)]),
        FakeHl7Decoder(),
    )

    with pytest.raises(ValueError, match="interval_seconds"):
        tuple(poller.poll(interval_seconds=0, limit=1))


def test_poll_uses_explicit_limit_and_sleeper() -> None:
    sleeps: list[float] = []
    poller = Hl7Poller(
        FakeHl7Source([_response(HL7_BODY), _response(HL7_BODY)]),
        FakeHl7Decoder(),
        sleep=sleeps.append,
    )

    results = tuple(poller.poll(interval_seconds=0.25, limit=2))

    assert [result.state for result in results] == [
        Hl7PollState.DATA,
        Hl7PollState.UNCHANGED,
    ]
    assert sleeps == [0.25]
