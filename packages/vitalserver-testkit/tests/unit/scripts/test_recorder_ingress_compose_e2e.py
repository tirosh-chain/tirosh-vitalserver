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
                "spool": {
                    "pendingItems": 0,
                    "pendingBytes": 0,
                },
                "replay": {
                    "replayedEvents": 11,
                    "deadLetteredEvents": 3,
                    "pendingItems": 0,
                    "inFlightItems": 0,
                },
            },
            {
                "spool": {
                    "pendingItems": 0,
                    "pendingBytes": 0,
                },
                "replay": {
                    "replayedEvents": 16,
                    "deadLetteredEvents": 3,
                    "pendingItems": 0,
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
            "spool": {
                "pendingItems": 0,
                "pendingBytes": 0,
            },
            "replay": {
                "replayedEvents": 6,
                "deadLetteredEvents": 1,
                "pendingItems": 0,
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


def test_wait_for_replay_rejects_missing_proof_counters(
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
            "spool": {
                "pendingItems": 0,
                "pendingBytes": 0,
            },
            "replay": {
                "replayedEvents": 6,
                "pendingItems": 0,
                "inFlightItems": 0,
            },
        },
    )

    with pytest.raises(
        AssertionError,
        match=r"missing numeric field: replay\.deadLetteredEvents",
    ):
        e2e.wait_for_replay(
            "http://127.0.0.1:18080",
            baseline,
            6,
            timeout_seconds=1,
        )


def test_wait_for_replay_waits_for_pending_items_to_drain(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "replay": {
            "replayedEvents": 0,
            "deadLetteredEvents": 0,
        },
    }
    statuses = iter(
        [
            {
                "spool": {
                    "pendingItems": 1,
                    "pendingBytes": 512,
                },
                "replay": {
                    "replayedEvents": 1,
                    "deadLetteredEvents": 0,
                    "pendingItems": 1,
                    "inFlightItems": 0,
                },
            },
            {
                "spool": {
                    "pendingItems": 0,
                    "pendingBytes": 0,
                },
                "replay": {
                    "replayedEvents": 3,
                    "deadLetteredEvents": 0,
                    "pendingItems": 0,
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
        1,
        timeout_seconds=1,
    )

    assert status["replay"]["replayedEvents"] == 3


def test_replay_memory_guard_status_reads_adaptive_status() -> None:
    status = {
        "replay": {
            "adaptive": {
                "memoryGuardStatus": "healthy",
                "currentMaxBytesPerSecond": 20 * 1024 * 1024,
                "currentItemsPerTick": 1000,
                "currentConcurrency": 8,
                "lastDecision": "keep",
                "lastReason": "steady",
            },
        },
    }

    assert e2e.replay_memory_guard_status(status) == "healthy"
    assert e2e.replay_adaptive_summary(status) == {
        "memoryGuardStatus": "healthy",
        "currentMaxBytesPerSecond": 20 * 1024 * 1024,
        "currentItemsPerTick": 1000,
        "currentConcurrency": 8,
        "lastDecision": "keep",
        "lastReason": "steady",
    }
    assert (
        e2e.replay_adaptive_summary(
            {
                "replay": {
                    "adaptive": {
                        "unknownFutureField": "ignored",
                    },
                },
            }
        )
        == {}
    )
    assert e2e.replay_memory_guard_status({"replay": {"adaptive": {}}}) is None


def test_assert_memory_guard_loaded_rejects_unavailable_status() -> None:
    e2e.assert_memory_guard_loaded("healthy")
    e2e.assert_memory_guard_loaded("warm")

    with pytest.raises(AssertionError, match="memoryGuardStatus=unavailable"):
        e2e.assert_memory_guard_loaded("unavailable")

    with pytest.raises(AssertionError, match="memoryGuardStatus=None"):
        e2e.assert_memory_guard_loaded(None)


def test_compose_env_includes_optional_backpressure_limits() -> None:
    args = e2e.parse_args(
        [
            "--replay-batch-size",
            "13",
            "--replay-max-mib-per-second",
            "25",
            "--replay-min-concurrency",
            "2",
            "--replay-max-concurrency",
            "12",
            "--max-pending-items",
            "1",
            "--max-pending-bytes",
            "2048",
            "--max-payload-bytes",
            "1024",
        ]
    )

    env = e2e.compose_env(args)

    assert env["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] == "13"
    assert env["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"] == str(
        25 * 1024 * 1024
    )
    assert env["RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_CONCURRENCY"] == "2"
    assert env["RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_CONCURRENCY"] == "12"
    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS"] == "1"
    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES"] == "2048"
    assert env["RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES"] == "1024"


def test_status_only_main_uses_http_status_without_compose_or_redis(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    baseline = {
        "sendDataEventsObserved": 0,
        "spool": {
            "spooledEvents": 0,
            "rejectedEvents": 0,
            "writeFailures": 0,
            "pendingItems": 0,
            "pendingBytes": 0,
        },
        "replay": {
            "replayedEvents": 0,
            "retryableFailures": 0,
            "deadLetteredEvents": 0,
            "pendingItems": 0,
            "inFlightItems": 0,
        },
    }
    final = {
        "sendDataEventsObserved": 1,
        "spool": {
            "mode": "spool_and_replay",
            "spooledEvents": 1,
            "rejectedEvents": 0,
            "writeFailures": 0,
            "pendingItems": 0,
            "pendingBytes": 0,
        },
        "replay": {
            "replayedEvents": 1,
            "retryableFailures": 0,
            "deadLetteredEvents": 0,
            "pendingItems": 0,
            "inFlightItems": 0,
            "replayLagSeconds": 0,
            "adaptive": {
                "memoryGuardStatus": "healthy",
                "currentConcurrency": 8,
            },
        },
    }

    monkeypatch.setattr(
        e2e, "run", lambda *args, **kwargs: pytest.fail("compose should not run")
    )
    monkeypatch.setattr(e2e, "wait_for_status", lambda *args, **kwargs: None)
    monkeypatch.setattr(e2e, "read_status", lambda _base_url: baseline)
    monkeypatch.setattr(e2e, "run_testkit_stream", lambda *args, **kwargs: None)
    monkeypatch.setattr(e2e, "wait_for_replay", lambda *args, **kwargs: final)
    monkeypatch.setattr(
        e2e,
        "redis_list_lengths",
        lambda *args, **kwargs: pytest.fail("redis should not be inspected"),
    )
    monkeypatch.setattr(
        e2e,
        "reset_redis_lists",
        lambda *args, **kwargs: pytest.fail("redis should not be reset"),
    )
    monkeypatch.setattr(
        e2e,
        "inspect_compose_container",
        lambda *args, **kwargs: pytest.fail("container should not be inspected"),
    )

    exit_code = e2e.main(
        [
            "--status-only",
            "--require-memory-guard",
            "--recorders",
            "1",
            "--max-messages",
            "1",
        ]
    )

    assert exit_code == 0
    output = json.loads(capsys.readouterr().out)
    assert output["ok"] is True
    assert output["proofScope"] == "status-only"
    assert output["appStabilityAsserted"] is False
    assert output["redis"] is None
    assert output["memoryGuardStatus"] == "healthy"
    assert output["adaptive"]["currentConcurrency"] == 8


def test_status_only_main_rejects_dirty_baseline(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "spool": {
            "pendingItems": 1,
            "pendingBytes": 512,
        },
        "replay": {
            "pendingItems": 1,
            "inFlightItems": 0,
        },
    }

    monkeypatch.setattr(
        e2e, "run", lambda *args, **kwargs: pytest.fail("compose should not run")
    )
    monkeypatch.setattr(e2e, "wait_for_status", lambda *args, **kwargs: None)
    monkeypatch.setattr(e2e, "read_status", lambda _base_url: baseline)
    monkeypatch.setattr(
        e2e,
        "run_testkit_stream",
        lambda *args, **kwargs: pytest.fail("testkit should not run"),
    )

    with pytest.raises(
        AssertionError,
        match=r"status-only baseline spool\.pendingItems=1",
    ):
        e2e.main(
            [
                "--status-only",
                "--recorders",
                "1",
                "--max-messages",
                "1",
            ]
        )


def test_status_only_main_rejects_missing_baseline_fields(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "spool": {
            "pendingBytes": 0,
        },
        "replay": {
            "pendingItems": 0,
            "inFlightItems": 0,
        },
    }

    monkeypatch.setattr(
        e2e, "run", lambda *args, **kwargs: pytest.fail("compose should not run")
    )
    monkeypatch.setattr(e2e, "wait_for_status", lambda *args, **kwargs: None)
    monkeypatch.setattr(e2e, "read_status", lambda _base_url: baseline)
    monkeypatch.setattr(
        e2e,
        "run_testkit_stream",
        lambda *args, **kwargs: pytest.fail("testkit should not run"),
    )

    with pytest.raises(
        AssertionError,
        match=r"missing numeric field: spool\.pendingItems",
    ):
        e2e.main(
            [
                "--status-only",
                "--recorders",
                "1",
                "--max-messages",
                "1",
            ]
        )


def test_status_only_main_rejects_boolean_baseline_fields(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    baseline = {
        "spool": {
            "pendingItems": False,
            "pendingBytes": 0,
        },
        "replay": {
            "pendingItems": 0,
            "inFlightItems": 0,
        },
    }

    monkeypatch.setattr(
        e2e, "run", lambda *args, **kwargs: pytest.fail("compose should not run")
    )
    monkeypatch.setattr(e2e, "wait_for_status", lambda *args, **kwargs: None)
    monkeypatch.setattr(e2e, "read_status", lambda _base_url: baseline)
    monkeypatch.setattr(
        e2e,
        "run_testkit_stream",
        lambda *args, **kwargs: pytest.fail("testkit should not run"),
    )

    with pytest.raises(
        AssertionError,
        match=r"missing numeric field: spool\.pendingItems",
    ):
        e2e.main(
            [
                "--status-only",
                "--recorders",
                "1",
                "--max-messages",
                "1",
            ]
        )


def test_status_only_main_rejects_app_stability_assertion() -> None:
    with pytest.raises(
        AssertionError,
        match="status-only proof cannot assert app stability without Docker inspect",
    ):
        e2e.main(
            [
                "--status-only",
                "--assert-app-stable",
                "--recorders",
                "1",
                "--max-messages",
                "1",
            ]
        )


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
