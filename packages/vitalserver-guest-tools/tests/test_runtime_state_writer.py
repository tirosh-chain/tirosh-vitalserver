from __future__ import annotations

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.runtime import state_writer
from tirosh_guest_tools.adapters.outbound.runtime.probes import ProbeError


def test_runtime_state_document_reports_probe_failures(
    monkeypatch: MonkeyPatch,
) -> None:
    def missing_ip(probe_errors: list[ProbeError]) -> str | None:
        state_writer.append_probe_error(probe_errors, "vmIP", "missing")
        return None

    monkeypatch.setattr(state_writer, "first_non_loopback_ip", missing_ip)
    monkeypatch.setattr(state_writer, "boot_id", lambda errors: "boot-1")
    monkeypatch.setattr(state_writer, "compose_services", lambda errors: [])
    monkeypatch.setattr(state_writer, "cpu_usage_percent", lambda errors: 10.0)
    monkeypatch.setattr(
        state_writer,
        "memory_usage",
        lambda errors: {"usedBytes": 1, "totalBytes": 2},
    )
    monkeypatch.setattr(
        state_writer,
        "disk_usage",
        lambda path, errors: {"usedBytes": 1, "totalBytes": 2},
    )
    monkeypatch.setattr(state_writer, "vitaldb_observation", lambda errors: None)

    document = state_writer.runtime_state_document()

    assert document["vmIP"] is None
    assert document["probeErrors"] == [{"source": "vmIP", "message": "missing"}]
