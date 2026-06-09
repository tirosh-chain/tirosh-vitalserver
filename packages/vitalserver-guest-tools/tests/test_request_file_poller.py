from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from tirosh_guest_tools.adapters.inbound import request_file_poller
from tirosh_guest_tools.contracts import RuntimeService


def test_dispatch_request_writes_prepare_shutdown_failure_when_unit_failed(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request_file = tmp_path / "prepare-update-shutdown.request"
    result_file = tmp_path / "prepare-update-shutdown-result.json"
    request_file.write_text(
        json.dumps({"requestId": "req-1", "version": "1.2.3"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(
        request_file_poller,
        "PREPARE_UPDATE_SHUTDOWN_REQUEST_FILE",
        request_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "REQUEST_FILE",
        request_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "RESULT_FILE",
        result_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "utc_now",
        lambda: "2026-06-01T00:00:00Z",
    )
    monkeypatch.setattr(
        request_file_poller,
        "service_active_state",
        lambda service: "failed",
    )
    starts: list[str] = []
    monkeypatch.setattr(
        request_file_poller,
        "systemctl",
        lambda *args, **kwargs: _record_systemctl(starts, *args),
    )

    request_file_poller.dispatch_request(
        request_file,
        RuntimeService.PREPARE_UPDATE_SHUTDOWN.value,
        "prepare-update-shutdown",
    )

    result = json.loads(result_file.read_text(encoding="utf-8"))
    assert result["requestId"] == "req-1"
    assert result["status"] == "failed"
    assert result["step"] == "dispatch"
    assert result["reasonCodes"] == ["guest-command-unit-failed"]
    assert RuntimeService.PREPARE_UPDATE_SHUTDOWN.value in result["message"]
    assert starts == []


def test_dispatch_request_writes_prepare_shutdown_failure_when_start_fails(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request_file = tmp_path / "prepare-update-shutdown.request"
    result_file = tmp_path / "prepare-update-shutdown-result.json"
    request_file.write_text(
        json.dumps({"requestId": "req-2", "version": "1.2.4"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(
        request_file_poller,
        "PREPARE_UPDATE_SHUTDOWN_REQUEST_FILE",
        request_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "REQUEST_FILE",
        request_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "RESULT_FILE",
        result_file,
    )
    monkeypatch.setitem(
        request_file_poller.write_dispatch_failure_result.__globals__,
        "utc_now",
        lambda: "2026-06-01T00:00:00Z",
    )
    monkeypatch.setattr(
        request_file_poller,
        "service_active_state",
        lambda service: "inactive",
    )
    monkeypatch.setattr(
        request_file_poller,
        "systemctl",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            ["systemctl", *args],
            1,
            "",
            "dependency failed",
        ),
    )

    request_file_poller.dispatch_request(
        request_file,
        RuntimeService.PREPARE_UPDATE_SHUTDOWN.value,
        "prepare-update-shutdown",
    )

    result = json.loads(result_file.read_text(encoding="utf-8"))
    assert result["requestId"] == "req-2"
    assert result["status"] == "failed"
    assert result["reasonCodes"] == ["guest-command-dispatch-failed"]
    assert "dependency failed" in result["message"]


def _record_systemctl(
    calls: list[str],
    *args: str,
) -> subprocess.CompletedProcess[str]:
    calls.append(":".join(args))
    return subprocess.CompletedProcess(["systemctl", *args], 0, "", "")
