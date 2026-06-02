from __future__ import annotations

import json
from pathlib import Path

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.observability import writer
from tirosh_guest_tools.domain.operations import ObservationPhase


def test_safe_phase_keeps_snapshot_file_names_stable() -> None:
    assert writer.safe_phase("shutdown pre/stop") == "shutdown-pre-stop"
    assert writer.safe_phase("  ") == ObservationPhase.MANUAL.value


def test_write_oneshot_snapshot_writes_latest_and_history_files(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setattr(writer, "OBSERVABILITY_DIR", tmp_path)

    document = {
        "schemaVersion": 1,
        "observedAt": "2026-06-01T00:00:00Z",
        "phase": ObservationPhase.SHUTDOWN_PRE_STOP.value,
    }

    writer.write_oneshot_snapshot(
        ObservationPhase.SHUTDOWN_PRE_STOP.value,
        document,
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
