from __future__ import annotations

import subprocess
from datetime import UTC, datetime
from pathlib import Path

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.runtime import collector, state_writer
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    ProbeError,
    RuntimeResourceUsage,
)


def test_runtime_state_document_reports_probe_failures(
    monkeypatch: MonkeyPatch,
) -> None:
    def missing_ip(probe_errors: list[ProbeError]) -> str | None:
        collector.append_probe_error(probe_errors, "vmIP", "missing")
        return None

    monkeypatch.setattr(collector, "first_non_loopback_ip", missing_ip)
    monkeypatch.setattr(collector, "boot_id", lambda errors: "boot-1")
    monkeypatch.setattr(collector, "cpu_usage_percent", lambda errors: 10.0)
    monkeypatch.setattr(
        collector,
        "memory_usage",
        lambda errors: RuntimeResourceUsage(used_bytes=1, total_bytes=2),
    )
    monkeypatch.setattr(
        collector,
        "disk_usage",
        lambda path, errors: RuntimeResourceUsage(used_bytes=1, total_bytes=2),
    )
    document = state_writer.runtime_state_document(
        guest_http="200",
        redis_ui_http="200",
        swagger_ui_http="200",
    ).as_json()

    assert document["vmIP"] is None
    assert document["probeErrors"] == [{"source": "vmIP", "message": "missing"}]


def test_write_runtime_state_document_updates_vitaldb_postgres_read_models(
    tmp_path: Path,
) -> None:
    writer = VitalDBReadModelWriterSpy()
    state = GuestRuntimeState(
        updated_at="2026-07-01T00:00:01+00:00",
        vm_ip="192.168.64.2",
        boot_id="boot-1",
        cpu_usage_percent=10.0,
        guest_http=None,
        memory=None,
        probe_errors=[],
        redis_ui_http=None,
        system_disk=None,
        disk_health=None,
        swagger_ui_http=None,
        vital_files_disk=None,
    )
    observation = {
        "observedAt": "2026-07-01T00:00:00+00:00",
        "recorders": [
            {
                "vrcode": "VR-001",
                "online": True,
                "stale": False,
            }
        ],
        "beds": [
            {
                "bedID": "bed-a",
                "name": "OR-A",
                "vrcode": "VR-001",
                "lastSeenAt": "2026-07-01T00:00:00+00:00",
                "patientConnected": True,
                "online": True,
            }
        ],
        "readIssues": [],
    }

    state_writer.write_runtime_state_document(
        tmp_path / "runtime-state.json",
        state,
        vitaldb_read_model=writer,
        vitaldb_observation=observation,
    )

    assert writer.schema_ensured is True
    assert writer.observation == observation
    assert writer.observation_observed_at == datetime(2026, 7, 1, tzinfo=UTC)
    assert writer.relationship_history == {
        "state": "loaded",
        "assignments": [
            {
                "assignmentID": (
                    "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
                ),
                "bedID": "bed-a",
                "bedName": "OR-A",
                "vrcode": "VR-001",
                "startedAt": "2026-07-01T00:00:00+00:00",
                "endedAt": None,
                "lastSeenAt": "2026-07-01T00:00:00+00:00",
                "lastObservedAt": "2026-07-01T00:00:00+00:00",
                "status": "online",
                "patientConnected": True,
                "observationCount": 1,
            }
        ],
        "events": [],
        "readError": None,
    }
    assert writer.relationship_observed_at == datetime(2026, 7, 1, tzinfo=UTC)


def test_write_runtime_state_document_uses_previous_relationship_history(
    tmp_path: Path,
) -> None:
    writer = VitalDBReadModelWriterSpy(
        previous_relationship_history={
            "state": "loaded",
            "assignments": [
                {
                    "assignmentID": (
                        "assignment:bed-a:VR-001:2026-07-01T00:00:00+00:00"
                    ),
                    "bedID": "bed-a",
                    "bedName": "OR-A",
                    "vrcode": "VR-001",
                    "startedAt": "2026-07-01T00:00:00+00:00",
                    "endedAt": None,
                    "lastSeenAt": "2026-07-01T00:00:00+00:00",
                    "lastObservedAt": "2026-07-01T00:00:00+00:00",
                    "status": "online",
                    "patientConnected": True,
                    "observationCount": 1,
                }
            ],
            "events": [],
            "readError": None,
        }
    )
    state = GuestRuntimeState(
        updated_at="2026-07-01T00:01:01+00:00",
        vm_ip="192.168.64.2",
        boot_id="boot-1",
        cpu_usage_percent=10.0,
        guest_http=None,
        memory=None,
        probe_errors=[],
        redis_ui_http=None,
        system_disk=None,
        disk_health=None,
        swagger_ui_http=None,
        vital_files_disk=None,
    )
    observation = {
        "observedAt": "2026-07-01T00:01:00+00:00",
        "recorders": [
            {
                "vrcode": "VR-001",
                "online": True,
                "stale": False,
            }
        ],
        "beds": [
            {
                "bedID": "bed-a",
                "name": "OR-A",
                "vrcode": "VR-001",
                "lastSeenAt": "2026-07-01T00:01:00+00:00",
                "patientConnected": True,
                "online": True,
            }
        ],
        "readIssues": [],
    }

    state_writer.write_runtime_state_document(
        tmp_path / "runtime-state.json",
        state,
        vitaldb_read_model=writer,
        vitaldb_observation=observation,
    )

    assert writer.previous_relationship_history_read is True
    assert writer.relationship_history is not None
    assert writer.relationship_history["assignments"][0]["startedAt"] == (
        "2026-07-01T00:00:00+00:00"
    )
    assert writer.relationship_history["assignments"][0]["observationCount"] == 2


def test_write_runtime_state_document_skips_vitaldb_read_models_without_observation(
    tmp_path: Path,
) -> None:
    writer = VitalDBReadModelWriterSpy()
    state = GuestRuntimeState(
        updated_at="2026-07-01T00:00:01+00:00",
        vm_ip="192.168.64.2",
        boot_id="boot-1",
        cpu_usage_percent=10.0,
        guest_http=None,
        memory=None,
        probe_errors=[],
        redis_ui_http=None,
        system_disk=None,
        disk_health=None,
        swagger_ui_http=None,
        vital_files_disk=None,
    )

    state_writer.write_runtime_state_document(
        tmp_path / "runtime-state.json",
        state,
        vitaldb_read_model=writer,
    )

    assert writer.schema_ensured is False
    assert writer.observation is None
    assert writer.relationship_history is None


def test_http_probe_failure_remains_explicit(
    monkeypatch: MonkeyPatch,
) -> None:
    def failed_run(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args=[],
            returncode=7,
            stdout="",
            stderr="connection refused",
        )

    probe_errors: list[ProbeError] = []
    monkeypatch.setattr(collector.subprocess, "run", failed_run)

    status = collector.http_status(
        "guestHTTP",
        "http://127.0.0.1/ready",
        probe_errors,
    )

    assert status.as_status_text() == "failed"
    assert status.as_json() == {
        "status": "failed",
        "failed": True,
        "message": "connection refused",
        "exitCode": 7,
    }
    assert probe_errors == [
        ProbeError(source="guestHTTP", message="connection refused")
    ]


class VitalDBReadModelWriterSpy:
    def __init__(
        self,
        *,
        previous_relationship_history: dict[str, object] | None = None,
    ) -> None:
        self.schema_ensured = False
        self.observation: dict[str, object] | None = None
        self.observation_observed_at: datetime | None = None
        self.relationship_history: dict[str, object] | None = None
        self.relationship_observed_at: datetime | None = None
        self._previous_relationship_history = previous_relationship_history
        self.previous_relationship_history_read = False

    def ensure_schema(self) -> None:
        self.schema_ensured = True

    def previous_relationship_history(self) -> dict[str, object] | None:
        self.previous_relationship_history_read = True
        return self._previous_relationship_history

    def save_latest_observation(
        self,
        observation: dict[str, object],
        *,
        observed_at: datetime,
    ) -> None:
        self.observation = observation
        self.observation_observed_at = observed_at

    def save_relationship_history(
        self,
        relationship_history: dict[str, object],
        *,
        observed_at: datetime,
    ) -> None:
        self.relationship_history = relationship_history
        self.relationship_observed_at = observed_at
