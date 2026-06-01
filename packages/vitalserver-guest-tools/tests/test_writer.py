from __future__ import annotations

import json
from pathlib import Path

from pytest import MonkeyPatch

from tirosh_guest_tools.observability import writer


def test_safe_phase_keeps_snapshot_file_names_stable() -> None:
    assert writer.safe_phase("shutdown pre/stop") == "shutdown-pre-stop"
    assert writer.safe_phase("  ") == "manual"


def test_write_oneshot_snapshot_writes_latest_and_history_files(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setattr(writer, "OBSERVABILITY_DIR", tmp_path)

    document = {
        "schemaVersion": 1,
        "observedAt": "2026-06-01T00:00:00Z",
        "phase": "shutdown-pre-stop",
    }

    writer.write_oneshot_snapshot(
        "shutdown-pre-stop",
        document,
        "snapshot\n",
    )

    latest = json.loads((tmp_path / "shutdown-pre-stop.latest.json").read_text())
    assert latest["phase"] == "shutdown-pre-stop"
    assert (tmp_path / "shutdown-pre-stop.latest.log").read_text() == "snapshot\n"
    assert (
        tmp_path / "snapshots/20260601T000000Z-shutdown-pre-stop.json"
    ).is_file()
