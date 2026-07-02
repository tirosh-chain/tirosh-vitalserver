from __future__ import annotations

from pathlib import Path
from typing import Any

from tirosh_guest_tools.application import redis_backup


def test_redis_backup_returns_archive_without_request_result_file_contract(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    backup_dir = tmp_path / "backups" / "redis"
    result = tmp_path / "redis-backup-result.json"
    created: list[Path] = []

    monkeypatch.setattr(redis_backup, "BACKUP_DIR", backup_dir)
    monkeypatch.setattr(redis_backup, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(redis_backup, "utc_now", lambda: "2026-06-10T00:00:00Z")
    monkeypatch.setattr(redis_backup, "create_backup", created.append)

    outcome = redis_backup.run_redis_backup()

    expected_archive = backup_dir / "redis-20260610T000000Z.tar.gz"
    assert created == [expected_archive]
    assert outcome.archive == expected_archive
    assert not result.exists()
