from __future__ import annotations

import pytest

from scripts import recorder_ingress_compose_e2e as e2e


def test_counter_delta_reads_nested_status_fields() -> None:
    baseline = {
        "sendDataEventsObserved": 2,
        "spool": {"spooledEvents": 2},
        "replay": {"replayedEvents": 1, "deadLetteredEvents": 0},
    }
    current = {
        "sendDataEventsObserved": 8,
        "spool": {"spooledEvents": 8},
        "replay": {"replayedEvents": 7, "deadLetteredEvents": 0},
    }

    assert e2e.counter_delta(current, baseline, ("sendDataEventsObserved",)) == 6
    assert e2e.counter_delta(current, baseline, ("spool", "spooledEvents")) == 6
    assert e2e.counter_delta(current, baseline, ("replay", "replayedEvents")) == 6
    assert e2e.counter_delta(current, baseline, ("replay", "deadLetteredEvents")) == 0


def test_wait_for_replay_uses_replayed_delta_not_absolute_counter(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "replay": {
            "replayedEvents": 10,
            "deadLetteredEvents": 3,
        },
    }
    statuses = iter(
        [
            {
                "replay": {
                    "replayedEvents": 11,
                    "deadLetteredEvents": 3,
                    "inFlightItems": 0,
                },
            },
            {
                "replay": {
                    "replayedEvents": 16,
                    "deadLetteredEvents": 3,
                    "inFlightItems": 0,
                },
            },
        ]
    )

    monkeypatch.setattr(e2e, "read_status", lambda _base_url: next(statuses))
    monkeypatch.setattr(e2e.time, "sleep", lambda _seconds: None)

    status = e2e.wait_for_replay(
        "http://127.0.0.1:18080",
        baseline,
        6,
        timeout_seconds=1,
    )

    assert status["replay"]["replayedEvents"] == 16


def test_wait_for_replay_rejects_dead_letter_delta(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "replay": {
            "replayedEvents": 0,
            "deadLetteredEvents": 0,
        },
    }

    monkeypatch.setattr(
        e2e,
        "read_status",
        lambda _base_url: {
            "replay": {
                "replayedEvents": 6,
                "deadLetteredEvents": 1,
                "inFlightItems": 0,
            },
        },
    )
    monkeypatch.setattr(e2e.time, "sleep", lambda _seconds: None)

    with pytest.raises(RuntimeError, match="send_data replay did not complete"):
        e2e.wait_for_replay(
            "http://127.0.0.1:18080",
            baseline,
            6,
            timeout_seconds=0.01,
        )
