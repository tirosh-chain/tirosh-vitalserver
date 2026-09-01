"""Polling workflow for the legacy VitalServer HL7 snapshot endpoint."""

from __future__ import annotations

import hashlib
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum

from tirosh_vitalserver.testkit.application.ports import Hl7SourcePort
from tirosh_vitalserver.testkit.domain.hl7 import Hl7Message, parse_hl7_stream
from tirosh_vitalserver.testkit.errors import Hl7RequestError


class Hl7PollState(StrEnum):
    """Meaning of one successful HTTP poll."""

    DATA = "data"
    UNCHANGED = "unchanged"
    EMPTY = "empty"


@dataclass(frozen=True, slots=True)
class Hl7PollResult:
    """Parsed result of one successful ``GET /HL7`` request."""

    state: Hl7PollState
    polled_at: datetime
    response_bytes: int
    elapsed_seconds: float
    messages: tuple[Hl7Message, ...]


class Hl7Poller:
    """Owns response identity while repeatedly polling one VitalServer."""

    def __init__(
        self,
        source: Hl7SourcePort,
        *,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._source = source
        self._sleep = sleep
        self._last_digest: bytes | None = None

    def poll_once(self) -> Hl7PollResult:
        """Fetch and parse one snapshot without hiding HTTP or decode failures."""

        response = self._source.fetch_hl7()
        if not response.ok:
            raise Hl7RequestError(
                f"VitalServer /HL7 returned HTTP {response.status_code}"
            )

        messages = parse_hl7_stream(response.body)
        digest = hashlib.sha256(response.body).digest()

        if response.body == b"":
            state = Hl7PollState.EMPTY
        elif digest == self._last_digest:
            state = Hl7PollState.UNCHANGED
        else:
            state = Hl7PollState.DATA

        self._last_digest = digest

        return Hl7PollResult(
            state=state,
            polled_at=datetime.now(UTC),
            response_bytes=len(response.body),
            elapsed_seconds=response.elapsed_seconds,
            messages=messages,
        )

    def poll(
        self,
        *,
        interval_seconds: float = 1.0,
        limit: int | None = None,
    ) -> Iterator[Hl7PollResult]:
        """Yield snapshots until ``limit`` is reached or the caller interrupts."""

        if interval_seconds <= 0:
            raise ValueError("interval_seconds must be greater than zero")
        if limit is not None and limit <= 0:
            raise ValueError("limit must be greater than zero when provided")

        emitted = 0
        while limit is None or emitted < limit:
            yield self.poll_once()
            emitted += 1
            if limit is None or emitted < limit:
                self._sleep(interval_seconds)
