from __future__ import annotations

import json
from pathlib import Path

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.observability import writer
from tirosh_guest_tools.domain.observability import (
    DockerObservation,
    GuestObservabilitySnapshot,
    MountObservation,
    NetworkObservation,
    ObservabilityCollectorError,
    ObservabilityDaemonErrorEvent,
    ObservationDetail,
    StorageObservation,
    SystemdObservation,
)
from tirosh_guest_tools.domain.operations import ObservationPhase


def test_safe_phase_keeps_snapshot_file_names_stable() -> None:
    assert writer.safe_phase("shutdown pre/stop") == "shutdown-pre-stop"
    assert writer.safe_phase("  ") == ObservationPhase.MANUAL.value


def test_write_oneshot_snapshot_writes_latest_and_history_files(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setattr(writer, "OBSERVABILITY_DIR", tmp_path)

    snapshot = GuestObservabilitySnapshot(
        detail=ObservationDetail.ONESHOT,
        observed_at="2026-06-01T00:00:00Z",
        hostname="guest",
        boot_id="boot-id",
        uptime_seconds=1.0,
        phase=ObservationPhase.SHUTDOWN_PRE_STOP.value,
        systemd=SystemdObservation(system_state="running", failed_units=(), jobs=()),
        load_average=(),
        memory={},
        storage=StorageObservation(df=(), inodes=(), root_read_only=False),
        mounts=MountObservation(source="findmnt-text", lines=()),
        services={},
        docker=DockerObservation(version="", compose_version="", containers=()),
        network=NetworkObservation(addresses=(), routes=(), resolv_conf=None),
        runtime={},
        collector_errors=(),
    )

    writer.write_oneshot_snapshot(
        ObservationPhase.SHUTDOWN_PRE_STOP.value,
        snapshot,
        "snapshot\n",
    )

    latest_path = tmp_path / f"{ObservationPhase.SHUTDOWN_PRE_STOP.value}.latest.json"
    latest = json.loads(latest_path.read_text())
    assert latest["phase"] == ObservationPhase.SHUTDOWN_PRE_STOP.value
    assert (
        tmp_path / f"{ObservationPhase.SHUTDOWN_PRE_STOP.value}.latest.log"
    ).read_text() == "snapshot\n"
    assert (
        tmp_path / "snapshots/20260601T000000Z-shutdown-pre-stop.json"
    ).is_file()


def test_write_daemon_snapshot_records_collector_error_event(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setattr(writer, "OBSERVABILITY_DIR", tmp_path)

    snapshot = GuestObservabilitySnapshot(
        detail=ObservationDetail.DAEMON,
        observed_at="2026-06-01T00:00:00Z",
        hostname="guest",
        boot_id="boot-id",
        uptime_seconds=1.0,
        phase=None,
        systemd=SystemdObservation(system_state="running", failed_units=(), jobs=()),
        load_average=(),
        memory={},
        storage=StorageObservation(df=(), inodes=(), root_read_only=False),
        mounts=MountObservation(source="findmnt-text", lines=()),
        services={},
        docker=DockerObservation(version="", compose_version="", containers=()),
        network=NetworkObservation(addresses=(), routes=(), resolv_conf=None),
        runtime={},
        collector_errors=(
            ObservabilityCollectorError(source="/proc/uptime", message="missing"),
        ),
    )

    writer.write_daemon_snapshot(snapshot)

    event = json.loads((tmp_path / "events.jsonl").read_text())
    assert event == {
        "collectorErrors": [{"message": "missing", "source": "/proc/uptime"}],
        "observedAt": "2026-06-01T00:00:00Z",
        "schemaVersion": 1,
        "type": "collector-errors",
    }


def test_daemon_error_event_shape_is_owned_by_domain() -> None:
    event = ObservabilityDaemonErrorEvent(
        observed_at="2026-06-01T00:00:00Z",
        message="boom",
        traceback="trace",
    )

    assert event.as_json() == {
        "schemaVersion": 1,
        "type": "daemon-error",
        "observedAt": "2026-06-01T00:00:00Z",
        "message": "boom",
        "traceback": "trace",
    }
