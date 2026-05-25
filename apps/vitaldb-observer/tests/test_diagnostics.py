from __future__ import annotations

import json

import pytest

from vitaldb_observer.diagnostics import write_diagnostic_event
from vitaldb_observer.server import _recorder_counts


def test_write_diagnostic_event_outputs_json_line(
    capsys: pytest.CaptureFixture[str],
) -> None:
    write_diagnostic_event("observation_collected", recorderCount=2)

    captured = capsys.readouterr()
    payload = json.loads(captured.out)

    assert payload["schemaVersion"] == 1
    assert payload["source"] == "vitaldb-observer"
    assert payload["event"] == "observation_collected"
    assert payload["recorderCount"] == 2
    assert "observedAt" in payload


def test_recorder_counts_summarizes_online_and_stale_recorders() -> None:
    assert _recorder_counts(
        {
            "recorders": [
                {"online": True, "stale": False},
                {"online": False, "stale": True},
                {"online": True, "stale": True},
            ]
        }
    ) == {"online": 2, "stale": 2}
