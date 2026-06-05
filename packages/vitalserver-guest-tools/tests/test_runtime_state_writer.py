from __future__ import annotations

import subprocess

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.runtime import collector, state_writer
from tirosh_guest_tools.domain.runtime_state import ProbeError, RuntimeResourceUsage


def test_runtime_state_document_reports_probe_failures(
    monkeypatch: MonkeyPatch,
) -> None:
    def missing_ip(probe_errors: list[ProbeError]) -> str | None:
        collector.append_probe_error(probe_errors, "vmIP", "missing")
        return None

    monkeypatch.setattr(collector, "first_non_loopback_ip", missing_ip)
    monkeypatch.setattr(collector, "boot_id", lambda errors: "boot-1")
    monkeypatch.setattr(collector, "compose_services", lambda errors: [])
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
    monkeypatch.setattr(collector, "vitaldb_observation", lambda errors: None)

    document = state_writer.runtime_state_document(
        guest_http="200",
        redis_ui_http="200",
        swagger_ui_http="200",
    ).as_json()

    assert document["vmIP"] is None
    assert document["probeErrors"] == [{"source": "vmIP", "message": "missing"}]


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
