from __future__ import annotations

from typing import Any

from tirosh_guest_tools.application import redis_repair


def test_repair_datastore_runs_compose_repair_without_request_result_contract(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(redis_repair, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(
        redis_repair,
        "restart_runtime_compose",
        lambda: events.append("restart-compose"),
    )

    redis_repair.run_repair_datastore()

    assert events == ["restart-compose"]
