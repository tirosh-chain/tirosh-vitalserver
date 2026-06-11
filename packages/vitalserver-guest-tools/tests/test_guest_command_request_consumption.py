from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application import redis_backup, redis_repair


def test_redis_backup_consumes_request_before_backup_side_effects(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request = tmp_path / "redis-backup.request"
    result = tmp_path / "redis-backup-result.json"
    backup_dir = tmp_path / "backups" / "redis"
    request.write_text(json.dumps({"requestId": "backup-1"}), encoding="utf-8")
    events: list[str] = []

    monkeypatch.setattr(redis_backup, "REQUEST_FILE", request)
    monkeypatch.setattr(redis_backup, "RESULT_FILE", result)
    monkeypatch.setattr(redis_backup, "BACKUP_DIR", backup_dir)
    monkeypatch.setattr(redis_backup, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(redis_backup, "utc_now", lambda: "2026-06-10T00:00:00Z")
    monkeypatch.setattr(redis_backup, "read_retention_count", lambda: 30)
    monkeypatch.setattr(
        redis_backup,
        "create_backup",
        lambda archive: events.append(
            f"create-backup:request-exists={request.exists()}"
        ),
    )
    monkeypatch.setattr(redis_backup, "prune_backups", lambda retention: None)

    outcome = redis_backup.run_redis_backup()

    assert events == ["create-backup:request-exists=False"]
    assert outcome.request_id == "backup-1"
    document = json.loads(result.read_text(encoding="utf-8"))
    assert document["requestId"] == "backup-1"
    assert document["status"] == "completed"
    assert not request.exists()


def test_datastore_repair_consumes_request_before_compose_side_effects(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    request = tmp_path / "repair-datastore.request"
    result = tmp_path / "repair-datastore-result.json"
    request.write_text(json.dumps({"requestId": "repair-1"}), encoding="utf-8")
    events: list[str] = []

    monkeypatch.setattr(redis_repair, "REQUEST_FILE", request)
    monkeypatch.setattr(redis_repair, "RESULT_FILE", result)
    monkeypatch.setattr(redis_repair, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(redis_repair, "utc_now", lambda: "2026-06-10T00:00:00Z")
    monkeypatch.setattr(
        redis_repair,
        "restart_runtime_compose",
        lambda: events.append(f"restart-compose:request-exists={request.exists()}"),
    )

    redis_repair.run_repair_datastore()

    assert events == ["restart-compose:request-exists=False"]
    document = json.loads(result.read_text(encoding="utf-8"))
    assert document["requestId"] == "repair-1"
    assert document["status"] == "completed"
    assert not request.exists()
