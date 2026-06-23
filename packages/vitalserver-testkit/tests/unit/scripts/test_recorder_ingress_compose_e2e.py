from __future__ import annotations

import json
import subprocess

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


def test_compose_env_includes_optional_backpressure_limits() -> None:
    args = e2e.parse_args(
        [
            "--max-pending-items",
            "1",
            "--max-pending-bytes",
            "2048",
            "--max-payload-bytes",
            "1024",
        ]
    )

    env = e2e.compose_env(args)

    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS"] == "1"
    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES"] == "2048"
    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES"] == "1024"


def test_inspect_compose_container_reports_oom_and_restart_state(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_run(
        command: list[str],
        *,
        env: dict[str, str],
        capture: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        if command == ["docker", "compose", "ps", "-q", "app"]:
            return subprocess.CompletedProcess(command, 0, stdout="container-1\n")
        if command == ["docker", "inspect", "container-1"]:
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(
                    [
                        {
                            "RestartCount": 2,
                            "State": {
                                "OOMKilled": False,
                                "Status": "running",
                                "ExitCode": 0,
                            },
                        }
                    ]
                ),
            )
        raise AssertionError(f"unexpected command: {command}")

    monkeypatch.setattr(e2e, "run", fake_run)

    state = e2e.inspect_compose_container("docker", ["docker", "compose"], "app", {})

    assert state == {
        "containerId": "container-1",
        "oomKilled": False,
        "restartCount": 2,
        "status": "running",
        "exitCode": 0,
    }


def test_assert_app_stable_rejects_restart_change() -> None:
    with pytest.raises(AssertionError, match="restartCount changed"):
        e2e.assert_app_stable(
            {"oomKilled": False, "restartCount": 1, "status": "running"},
            {"oomKilled": False, "restartCount": 2, "status": "running"},
            "app",
        )


def test_assert_app_stable_rejects_oom_killed_container() -> None:
    with pytest.raises(AssertionError, match="oomKilled=true"):
        e2e.assert_app_stable(
            {"oomKilled": False, "restartCount": 1, "status": "running"},
            {"oomKilled": True, "restartCount": 1, "status": "running"},
            "app",
        )
